package com.naveenraj.taskrelay

import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** A task occurrence: which task, on which yyyy-MM-dd day. */
data class TaskDay(val taskId: String, val date: String)

/** Wall-clock to instant conversion, shared by the planner and the zone-change re-resolve. */
object Times {
    private val HHMM: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

    /**
     * Resolves a local date + time in [zone]. DST gap -> shifted forward by the gap length; DST overlap -> the earlier offset
     * (this is exactly what ZonedDateTime.of(LocalDate, LocalTime, ZoneId) does). Returns null for malformed input.
     */
    fun resolve(date: String, time: String, zone: ZoneId): Long? = try {
        ZonedDateTime.of(LocalDate.parse(date), LocalTime.parse(time), zone).toInstant().toEpochMilli()
    } catch (_: Exception) {
        null
    }

    /** Normalises "H:mm" / "HH:mm:ss" to "HH:mm"; null when malformed. */
    fun normalizeTime(time: String): String? = try {
        LocalTime.parse(time).format(HHMM)
    } catch (_: Exception) {
        null
    }

    fun hhmm(h: Int, m: Int): String = String.format(Locale.ROOT, "%02d:%02d", h, m)

    /** "HHmm" of an instant in [zone] (used in snooze keys). */
    fun compactHhmm(ms: Long, zone: ZoneId): String =
        Instant.ofEpochMilli(ms).atZone(zone).format(DateTimeFormatter.ofPattern("HHmm"))

    fun localHhmm(ms: Long, zone: ZoneId): String =
        Instant.ofEpochMilli(ms).atZone(zone).format(HHMM)

    fun localDate(ms: Long, zone: ZoneId): LocalDate = Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
}

/**
 * Turns a server feed into the list of native entries to schedule. PURE and deterministic: no clocks, no Android, no I/O
 * (the caller injects `now` and the zone), so it is fully unit-testable on the JVM.
 */
object FeedPlanner {
    const val MAX_ENTRIES = 400
    const val REMINDER_DAYS = 14
    const val MIDNIGHT_TIME = "00:01"

    /**
     * How long after its nominal time an entry that has NOT fired yet is still kept. Without exact-alarm permission Android delivers
     * an inexact alarm anywhere in a window that it caps at one hour, so a sync inside that window must not drop (and cancel) it.
     * Firing removes an entry from the store, so "stored and past its time" means "still waiting to be delivered".
     */
    const val PENDING_GRACE_MS = 65 * 60_000L

    /**
     * @param pendingCompletes (taskId, date) pairs that have an un-synced `complete` record: the feed still lists them as open,
     *   but the user already completed them, so they must not ring.
     * @param existingSnoozes native-owned snooze entries currently stored; kept unless the feed shows they are obsolete.
     * @param carryOver stored entries from the previous plan; the alarm/notification ones dated beyond the feed's authoritative
     *   range (window.covered_until, when the server capped the list) are kept instead of being cancelled for being absent.
     */
    fun plan(
        feed: Feed,
        nowMs: Long,
        zone: ZoneId,
        pendingCompletes: Set<TaskDay>,
        existingSnoozes: List<Entry>,
        carryOver: List<Entry> = emptyList(),
    ): List<Entry> {
        val byKey = LinkedHashMap<String, Entry>()
        val storedByKey = carryOver.associateBy { it.key }

        // 1. Feed alarms. Past instants are dropped, never moved to tomorrow.
        for (a in feed.alarms) {
            if (TaskDay(a.taskId, a.date) in pendingCompletes) continue
            val time = Times.normalizeTime(a.time) ?: continue
            val trigger = Times.resolve(a.date, time, zone) ?: continue
            val kind = if (a.kind == Kind.ALARM) Kind.ALARM else Kind.NOTIFICATION
            val key = Entry.keyFor(kind, a.taskId, a.date)
            if (trigger <= nowMs) {
                // Past its nominal time. If it is still stored it has not fired (firing removes it) and Android may yet deliver it late,
                // so keep that entry; never create one from the feed, or an alarm that already fired would ring a second time.
                val waiting = storedByKey[key]
                if (waiting != null && waiting.triggerMs == trigger && !waiting.isExpired(nowMs)) byKey[key] = waiting
                continue
            }
            byKey[key] = Entry(key, kind, a.taskId, a.date, time, a.title, trigger)
        }

        // 2. Alarms the feed is not authoritative for (it was capped at covered_until) are carried over, not cancelled.
        val covered = feed.window.coveredUntil
        if (covered.isNotEmpty()) {
            for (e in carryOver) {
                if (e.kind != Kind.ALARM && e.kind != Kind.NOTIFICATION) continue
                val beyond = e.date > covered || (feed.window.truncated && e.date == covered)
                if (!beyond || e.triggerMs <= nowMs || e.key in byKey) continue
                if (e.taskId != null && TaskDay(e.taskId, e.date) in pendingCompletes) continue
                byKey[e.key] = e
            }
        }

        // 3. Reminders + midnight refresh triggers.
        for (e in plannedReminders(feed.settings, carryOver, nowMs, zone)) byKey[e.key] = e

        // 4. Native-owned snoozes survive a re-plan unless the feed shows they are obsolete.
        for (s in existingSnoozes) {
            if (s.kind != Kind.SNOOZE || s.isExpired(nowMs)) continue
            val tid = s.taskId
            if (tid != null) {
                if (TaskDay(tid, s.date) in pendingCompletes) continue
                if (feedCovers(feed, s.date) && feed.alarms.none { it.taskId == tid && it.date == s.date }) continue
            }
            byKey[s.key] = s
        }

        return byKey.values.sortedWith(ORDER).take(MAX_ENTRIES)
    }

    /** `reminder_daily` / `reminder_eod` for each of the next 14 days plus a `midnight` entry per day; instants <= now are dropped. */
    fun planReminders(settings: FeedSettings?, nowMs: Long, zone: ZoneId, keepAfterMs: Long = nowMs): List<Entry> {
        val out = ArrayList<Entry>()
        val today = Times.localDate(nowMs, zone)
        for (i in 0 until REMINDER_DAYS) {
            val date = today.plusDays(i.toLong()).toString()
            if (settings?.dailyReminderOn == true) {
                add(out, Kind.REMINDER_DAILY, date, Times.hhmm(settings.dailyReminderHour, settings.dailyReminderMin), "Daily reminder", keepAfterMs, zone)
            }
            if (settings?.endOfDayOn == true) {
                add(out, Kind.REMINDER_EOD, date, Times.hhmm(settings.endOfDayHour, settings.endOfDayMin), "End of day", keepAfterMs, zone)
            }
        }
        // Midnight triggers: the next 14 local midnights (00:01 of tomorrow ... of today+14).
        for (i in 0..REMINDER_DAYS) {
            val date = today.plusDays(i.toLong()).toString()
            add(out, Kind.MIDNIGHT, date, MIDNIGHT_TIME, "Daily refresh", keepAfterMs, zone)
        }
        return out
    }

    /**
     * Plan used when the server said 304 (nothing changed): keep the stored task entries, drop what has passed or been completed,
     * and top the reminder/midnight horizon up from the stored settings so it never runs dry.
     */
    fun replan(
        stored: List<Entry>,
        settings: FeedSettings?,
        nowMs: Long,
        zone: ZoneId,
        pendingCompletes: Set<TaskDay>,
    ): List<Entry> {
        val byKey = LinkedHashMap<String, Entry>()
        for (e in stored) {
            if (!Kind.isTaskKind(e.kind) || e.isExpired(nowMs)) continue
            if (e.taskId != null && TaskDay(e.taskId, e.date) in pendingCompletes) continue
            byKey[e.key] = e
        }
        for (e in plannedReminders(settings, stored, nowMs, zone)) byKey[e.key] = e
        return byKey.values.sortedWith(ORDER).take(MAX_ENTRIES)
    }

    /** Future reminders and midnight triggers, plus stored ones past their time that have not fired yet (see [PENDING_GRACE_MS]). */
    private fun plannedReminders(settings: FeedSettings?, stored: List<Entry>, nowMs: Long, zone: ZoneId): List<Entry> {
        val storedByKey = stored.associateBy { it.key }
        return planReminders(settings, nowMs, zone, keepAfterMs = nowMs - PENDING_GRACE_MS).filter { e ->
            e.triggerMs > nowMs || storedByKey[e.key]?.let { it.triggerMs == e.triggerMs && !it.isExpired(nowMs) } == true
        }
    }

    private fun Entry.isExpired(nowMs: Long): Boolean = triggerMs <= nowMs - PENDING_GRACE_MS

    private fun add(out: MutableList<Entry>, kind: String, date: String, time: String, title: String, keepAfterMs: Long, zone: ZoneId) {
        val trigger = Times.resolve(date, time, zone) ?: return
        if (trigger <= keepAfterMs) return
        out.add(Entry(Entry.keyFor(kind, null, date), kind, null, date, time, title, trigger))
    }

    /** Does the feed speak for this date (inside [window.from, covered_until])? Outside it we know nothing, so we keep the snooze. */
    private fun feedCovers(feed: Feed, date: String): Boolean {
        val w = feed.window
        if (w.from.isEmpty()) return false
        val end = if (w.coveredUntil.isNotEmpty()) w.coveredUntil else w.to
        return date >= w.from && date <= end
    }

    val ORDER: Comparator<Entry> = compareBy<Entry>({ it.triggerMs }, { it.key })
}
