package com.naveenraj.taskrelay

import java.io.File
import java.time.Instant

object TestFixtures {
    /** Walks up from the working directory until web/test/fixtures/sync.json exists (the real server example). */
    fun syncJson(): String {
        var dir: File? = File(System.getProperty("user.dir")!!).absoluteFile
        while (dir != null) {
            val f = File(dir, "web/test/fixtures/sync.json")
            if (f.isFile) return f.readText(Charsets.UTF_8)
            dir = dir.parentFile
        }
        throw AssertionError("web/test/fixtures/sync.json not found above ${System.getProperty("user.dir")}")
    }

    fun feed(
        alarms: List<FeedAlarm> = emptyList(),
        settings: FeedSettings = FeedSettings(dailyReminderOn = false, endOfDayOn = false),
        from: String = "2026-11-06",
        to: String = "2026-11-19",
        covered: String = "2026-11-19",
        truncated: Boolean = false,
    ) = Feed(
        version = "W/\"test\"",
        serverTime = "2026-11-06T12:00:00Z",
        timezone = "UTC",
        today = FeedToday(from, 0, 0, 0, emptyList(), emptyList()),
        window = FeedWindow(from, to, covered, truncated),
        alarms = alarms,
        settings = settings,
    )

    fun alarm(taskId: String, date: String, time: String, kind: String = Kind.NOTIFICATION, title: String = "T $taskId") =
        FeedAlarm(taskId, date, time, title, kind, 30)

    fun ms(iso: String): Long = Instant.parse(iso).toEpochMilli()

    fun entry(kind: String, taskId: String?, date: String, time: String, trigger: Long, title: String = "t", orig: String? = null) =
        Entry(Entry.keyFor(kind, taskId, date), kind, taskId, date, time, title, trigger, orig)
}
