package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class TodayTask(val id: String, val title: String, val done: Boolean, val isTop: Boolean, val durationMin: Int)

/**
 * Today's numbers as the reminders and the widget read them. [pending] is the overlay of completes that were tapped but are not
 * yet confirmed by the server ("taskId|date"), so a tapped task shows done immediately.
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
) {
    /** Marks one task done (if it is today's and still open) and remembers it in the pending overlay. Idempotent. */
    fun withCompleted(taskId: String, completedDate: String): TodayData {
        val marker = "$taskId|$completedDate"
        val already = marker in pending
        val nextPending = if (already) pending else pending + marker
        if (completedDate != date) return copy(pending = nextPending)
        val nextDone = if (planned > done) done + 1 else done // never more done than planned
        val idx = tasks.indexOfFirst { it.id == taskId }
        if (idx >= 0) {
            if (tasks[idx].done) return copy(pending = nextPending)
            val nextTasks = tasks.toMutableList().also { it[idx] = it[idx].copy(done = true) }
            return copy(tasks = nextTasks, done = nextDone, pending = nextPending)
        }
        // Not in the (capped) task list: it is an open task beyond the first 25. Count it once.
        return if (already) copy(pending = nextPending) else copy(done = nextDone, pending = nextPending)
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
        put("pending", JSONArray(pending))
        put("updatedMs", updatedMs)
    }

    companion object {
        const val MAX_TASKS = 25

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
        )
    }
}

/** A small JSON file the widget, the reminders and the Complete path all read and write under one lock. */
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
