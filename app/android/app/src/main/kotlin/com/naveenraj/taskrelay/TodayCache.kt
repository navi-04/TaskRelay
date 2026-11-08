package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class TodayTask(val id: String, val title: String, val done: Boolean, val isTop: Boolean, val durationMin: Int)

/** One of today's timed tasks (the blocker reads these; it never needs the untimed ones). See [FeedBlock] and [TimeBlock]. */
data class TodayBlock(val id: String, val title: String, val startTime: String, val endTime: String?, val durationMin: Int, val done: Boolean) {
    /** Minutes since midnight, or null when this task has no usable block (an end alone, no length, malformed times). */
    val span: TimeBlock.Span? get() = TimeBlock.of(startTime, endTime, durationMin)
}

/**
 * Today's numbers as the reminders, the widget and the app blocker read them. [pending] is the overlay of completes that were
 * tapped but are not yet confirmed by the server ("taskId|date"), so a tapped task shows done immediately. [blocks] are today's
 * tasks that have a start time (empty for a cache written before blocks existed, or by an older server).
 */
data class TodayData(
    val date: String,
    val planned: Int,
    val done: Int,
    val overdueCount: Int,
    val top: List<String>,
    val tasks: List<TodayTask>,
    val pending: List<String> = emptyList(),
    val updatedMs: Long = 0L,
    val blocks: List<TodayBlock> = emptyList(),
) {
    /**
     * Marks one task done (if it is today's and still open) and remembers it in the pending overlay. Idempotent. Its block (if it
     * has one) flips too, even when the task is beyond the first 25 in [tasks].
     */
    fun withCompleted(taskId: String, completedDate: String): TodayData {
        val marker = "$taskId|$completedDate"
        val already = marker in pending
        val nextPending = if (already) pending else pending + marker
        if (completedDate != date) return copy(pending = nextPending)
        val nextDone = if (planned > done) done + 1 else done // never more done than planned
        val bIdx = blocks.indexOfFirst { it.id == taskId }
        val blockWasDone = bIdx >= 0 && blocks[bIdx].done
        val nextBlocks = if (bIdx >= 0 && !blockWasDone) blocks.toMutableList().also { it[bIdx] = it[bIdx].copy(done = true) } else blocks
        val idx = tasks.indexOfFirst { it.id == taskId }
        if (idx >= 0) {
            if (tasks[idx].done) return copy(blocks = nextBlocks, pending = nextPending)
            val nextTasks = tasks.toMutableList().also { it[idx] = it[idx].copy(done = true) }
            return copy(tasks = nextTasks, blocks = nextBlocks, done = nextDone, pending = nextPending)
        }
        // Not in the (capped) task list: it is an open task beyond the first 25. Count it once (its block, if it was already done,
        // says the server counted it).
        return if (already || blockWasDone) copy(blocks = nextBlocks, pending = nextPending) else copy(blocks = nextBlocks, done = nextDone, pending = nextPending)
    }

    /** Applies every pending (taskId, date) pair to this snapshot. */
    fun withPendingApplied(pairs: Collection<TaskDay>): TodayData =
        pairs.fold(this) { acc, p -> acc.withCompleted(p.taskId, p.date) }

    fun toJson(): JSONObject = JSONObject().apply {
        put("date", date)
        put("planned", planned)
        put("done", done)
        put("overdue_count", overdueCount)
        put("top", JSONArray(top))
        put("tasks", JSONArray().also { a ->
            tasks.forEach { t ->
                a.put(JSONObject().apply {
                    put("id", t.id)
                    put("title", t.title)
                    put("done", t.done)
                    put("is_top", t.isTop)
                    put("duration_min", t.durationMin)
                })
            }
        })
        put("blocks", JSONArray().also { a ->
            blocks.forEach { b ->
                a.put(JSONObject().apply {
                    put("id", b.id)
                    put("title", b.title)
                    put("start_time", b.startTime)
                    put("end_time", b.endTime ?: JSONObject.NULL)
                    put("duration_min", b.durationMin)
                    put("done", b.done)
                })
            }
        })
        put("pending", JSONArray(pending))
        put("updatedMs", updatedMs)
    }

    companion object {
        const val MAX_TASKS = 25

        /** The server sends at most 50 blocks; the cache never keeps more. */
        const val MAX_BLOCKS = 50

        fun fromJson(o: JSONObject): TodayData = TodayData(
            date = o.optString("date", ""),
            planned = o.optInt("planned", 0),
            done = o.optInt("done", 0),
            overdueCount = o.optInt("overdue_count", 0),
            top = Json.strings(o.optJSONArray("top")),
            tasks = Json.objects(o.optJSONArray("tasks")).mapNotNull { t ->
                val id = Json.str(t, "id") ?: return@mapNotNull null
                TodayTask(id, t.optString("title", ""), t.optBoolean("done", false), t.optBoolean("is_top", false), t.optInt("duration_min", 0))
            },
            pending = Json.strings(o.optJSONArray("pending")),
            updatedMs = o.optLong("updatedMs", 0L),
            blocks = Json.objects(o.optJSONArray("blocks")).mapNotNull { b -> // absent in a cache written before blocks existed
                val id = Json.str(b, "id") ?: return@mapNotNull null
                val start = Json.str(b, "start_time") ?: return@mapNotNull null
                TodayBlock(id, b.optString("title", ""), start, Json.str(b, "end_time"), b.optInt("duration_min", 0), b.optBoolean("done", false))
            },
        )

        fun fromFeed(today: FeedToday, nowMs: Long): TodayData = TodayData(
            date = today.date,
            planned = today.planned,
            done = today.done,
            overdueCount = today.overdueCount,
            top = today.top,
            tasks = today.tasks.take(MAX_TASKS).map { TodayTask(it.id, it.title, it.done, it.isTop, it.durationMin) },
            pending = emptyList(),
            updatedMs = nowMs,
            blocks = today.blocks.take(MAX_BLOCKS).map { TodayBlock(it.id, it.title, it.startTime, it.endTime, it.durationMin, it.done) },
        )
    }
}

/** A small JSON file the widget, the reminders, the app blocker and the Complete path all read and write under one lock. */
class TodayCache(private val file: File) {

    fun read(): TodayData? = synchronized(LOCK) { readUnlocked() }

    /**
     * Replaces the cache with a fresh feed snapshot and re-applies [pendingProvider]'s unacked completes on top. The provider is
     * evaluated INSIDE the lock, so a Complete tapped while a sync is writing is never lost (it either shows up in the provider or
     * lands in [markDone] right after).
     */
    fun writeFeed(today: FeedToday, nowMs: Long, pendingProvider: () -> Collection<TaskDay>) {
        synchronized(LOCK) {
            val data = TodayData.fromFeed(today, nowMs).withPendingApplied(pendingProvider())
            writeUnlocked(data)
        }
    }

    /** Flips one task to done in the cache (and records it in the pending overlay). No-op without a cache. */
    fun markDone(taskId: String, date: String) {
        synchronized(LOCK) {
            val cur = readUnlocked() ?: return
            writeUnlocked(cur.withCompleted(taskId, date).copy(updatedMs = System.currentTimeMillis()))
        }
    }

    fun clear() {
        synchronized(LOCK) { file.delete() }
    }

    private fun readUnlocked(): TodayData? {
        val text = AtomicFiles.readText(file) ?: return null
        return try {
            TodayData.fromJson(JSONObject(text))
        } catch (_: Exception) {
            null
        }
    }

    private fun writeUnlocked(data: TodayData) {
        AtomicFiles.write(file, data.toJson().toString().toByteArray(Charsets.UTF_8))
    }

    companion object {
        val LOCK = Any()
    }
}
