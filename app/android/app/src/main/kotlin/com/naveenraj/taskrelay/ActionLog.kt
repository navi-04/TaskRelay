package com.naveenraj.taskrelay

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile

/**
 * Append-only log of user actions that still have to reach the server. One line per action:
 * `taskId|date|complete|tapEpochMs`. Task ids match ^[A-Za-z0-9_-]{8,64}$, so '|' can never appear inside a field.
 *
 *  - appends are fsync'd under a process-wide lock (a tap survives an immediate process death or battery pull);
 *  - [peek] returns the lines, [ack] removes exactly those lines (temp file + atomic rename), so two overlapping drains
 *    (worker + foreground sync) are safe: the loser's ack is a no-op;
 *  - the file is the single source of truth for "completed but not yet synced" (planner filter, widget overlay).
 */
class ActionLog(private val file: File) {

    /** Appends a raw line (must not contain a line break). The write is fsync'd before returning. */
    @Throws(IOException::class)
    fun append(line: String) {
        require(line.isNotEmpty() && '\n' !in line && '\r' !in line) { "invalid log line" }
        synchronized(LOCK) {
            file.absoluteFile.parentFile?.mkdirs()
            val needsNewline = endsWithoutNewline()
            FileOutputStream(file, true).use {
                it.write(((if (needsNewline) "\n" else "") + line + "\n").toByteArray(Charsets.UTF_8))
                it.flush()
                it.fd.sync()
            }
        }
    }

    /** Logs a Complete. Returns false (and logs nothing) when the ids are malformed. */
    fun appendComplete(taskId: String, date: String, tapMs: Long): Boolean {
        if (!ID_RE.matches(taskId) || !DATE_RE.matches(date) || tapMs <= 0L) return false
        append("$taskId|$date|$COMPLETE|$tapMs")
        return true
    }

    fun peek(): List<String> = synchronized(LOCK) { readLines() }

    /** Removes exactly the given lines (one occurrence per element). Lines that are not (or no longer) present are ignored. */
    fun ack(lines: Collection<String>) {
        if (lines.isEmpty()) return
        synchronized(LOCK) {
            val current = readLines()
            if (current.isEmpty()) return
            val toRemove = HashMap<String, Int>()
            for (l in lines) toRemove.merge(l, 1, Int::plus)
            val kept = ArrayList<String>(current.size)
            var removed = 0
            for (l in current) {
                val n = toRemove[l]
                if (n != null && n > 0) {
                    toRemove[l] = n - 1
                    removed++
                } else {
                    kept.add(l)
                }
            }
            if (removed == 0) return
            if (kept.isEmpty()) {
                file.delete()
            } else {
                AtomicFiles.write(file, kept.joinToString("") { it + "\n" }.toByteArray(Charsets.UTF_8))
            }
        }
    }

    fun count(): Int = peek().size

    fun clear() {
        synchronized(LOCK) { file.delete() }
    }

    /** (taskId, date) pairs that have a pending complete record. */
    fun pendingCompletes(): Set<TaskDay> {
        val out = HashSet<TaskDay>()
        for (l in peek()) parse(l)?.let { out.add(TaskDay(it.taskId, it.date)) }
        return out
    }

    fun hasComplete(taskId: String, date: String): Boolean = TaskDay(taskId, date) in pendingCompletes()

    private fun readLines(): List<String> {
        val text = AtomicFiles.readText(file) ?: return emptyList()
        return text.split('\n').map { it.trimEnd('\r') }.filter { it.isNotEmpty() }
    }

    private fun endsWithoutNewline(): Boolean {
        if (!file.exists() || file.length() == 0L) return false
        return try {
            RandomAccessFile(file, "r").use {
                it.seek(it.length() - 1)
                it.read() != '\n'.code
            }
        } catch (_: IOException) {
            false
        }
    }

    data class Record(val taskId: String, val date: String, val type: String, val tapMs: Long)

    companion object {
        const val COMPLETE = "complete"

        /** Process-wide: every ActionLog instance (worker, receivers, UI) serialises on this one lock. */
        val LOCK = Any()

        val ID_RE = Regex("^[A-Za-z0-9_-]{8,64}$")
        val DATE_RE = Regex("^\\d{4}-\\d{2}-\\d{2}$")

        fun parse(line: String): Record? {
            val p = line.split('|')
            if (p.size != 4) return null
            val ms = p[3].toLongOrNull() ?: return null
            if (!ID_RE.matches(p[0]) || !DATE_RE.matches(p[1]) || p[2] != COMPLETE) return null
            return Record(p[0], p[1], p[2], ms)
        }
    }
}
