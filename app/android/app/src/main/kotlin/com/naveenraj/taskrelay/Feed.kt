package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant

/** `GET /api/v1/sync` response (see web/lib/services/sync.ts and web/test/fixtures/sync.json). Pure data, no Android classes. */
data class Feed(
    val version: String,
    val serverTime: String,
    val timezone: String,
    val today: FeedToday,
    val window: FeedWindow,
    val alarms: List<FeedAlarm>,
    val settings: FeedSettings,
) {
    /** The instant the server built this feed, or null when it is malformed. */
    val serverTimeMs: Long? get() = runCatching { Instant.parse(serverTime).toEpochMilli() }.getOrNull()
}

data class FeedToday(
    val date: String,
    val planned: Int,
    val done: Int,
    val overdueCount: Int,
    val top: List<String>,
    val tasks: List<FeedTask>,
    /** Today's tasks that have a start time, earliest first (an older server sends none). */
    val blocks: List<FeedBlock> = emptyList(),
)

data class FeedTask(val id: String, val title: String, val done: Boolean, val isTop: Boolean, val durationMin: Int)

/** One of today's timed tasks: `start_time` always, `end_time` when set. Turn it into minutes with [TimeBlock.of]. */
data class FeedBlock(val id: String, val title: String, val startTime: String, val endTime: String?, val durationMin: Int, val done: Boolean)

data class FeedWindow(val from: String, val to: String, val coveredUntil: String, val truncated: Boolean)

data class FeedAlarm(val taskId: String, val date: String, val time: String, val title: String, val kind: String, val durationMin: Int)

data class FeedSettings(
    val dailyReminderOn: Boolean = true,
    val dailyReminderHour: Int = 9,
    val dailyReminderMin: Int = 0,
    val endOfDayOn: Boolean = false,
    val endOfDayHour: Int = 21,
    val endOfDayMin: Int = 0,
    val carryOverAlerts: Boolean = true,
    val estimationMode: String = "time",
    val dailyTimeLimitMin: Int = 480,
    val dailyCountLimit: Int = 10,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("daily_reminder_on", dailyReminderOn)
        put("daily_reminder_hour", dailyReminderHour)
        put("daily_reminder_min", dailyReminderMin)
        put("end_of_day_on", endOfDayOn)
        put("end_of_day_hour", endOfDayHour)
        put("end_of_day_min", endOfDayMin)
        put("carry_over_alerts", carryOverAlerts)
        put("estimation_mode", estimationMode)
        put("daily_time_limit_min", dailyTimeLimitMin)
        put("daily_count_limit", dailyCountLimit)
    }

    companion object {
        fun fromJson(o: JSONObject?): FeedSettings {
            if (o == null) return FeedSettings()
            val d = FeedSettings()
            return FeedSettings(
                dailyReminderOn = o.optBoolean("daily_reminder_on", d.dailyReminderOn),
                dailyReminderHour = o.optInt("daily_reminder_hour", d.dailyReminderHour).coerceIn(0, 23),
                dailyReminderMin = o.optInt("daily_reminder_min", d.dailyReminderMin).coerceIn(0, 59),
                endOfDayOn = o.optBoolean("end_of_day_on", d.endOfDayOn),
                endOfDayHour = o.optInt("end_of_day_hour", d.endOfDayHour).coerceIn(0, 23),
                endOfDayMin = o.optInt("end_of_day_min", d.endOfDayMin).coerceIn(0, 59),
                carryOverAlerts = o.optBoolean("carry_over_alerts", d.carryOverAlerts),
                estimationMode = Json.str(o, "estimation_mode") ?: d.estimationMode,
                dailyTimeLimitMin = o.optInt("daily_time_limit_min", d.dailyTimeLimitMin),
                dailyCountLimit = o.optInt("daily_count_limit", d.dailyCountLimit),
            )
        }
    }
}

/** org.json helpers: `optString` turns JSON null into the string "null", which we never want. */
object Json {
    fun str(o: JSONObject, key: String): String? = if (o.isNull(key)) null else o.optString(key).takeIf { it.isNotEmpty() }

    fun strings(a: JSONArray?): List<String> {
        if (a == null) return emptyList()
        val out = ArrayList<String>(a.length())
        for (i in 0 until a.length()) if (!a.isNull(i)) out.add(a.optString(i))
        return out
    }

    fun objects(a: JSONArray?): List<JSONObject> {
        if (a == null) return emptyList()
        val out = ArrayList<JSONObject>(a.length())
        for (i in 0 until a.length()) a.optJSONObject(i)?.let { out.add(it) }
        return out
    }
}

object FeedParser {
    /** Parses a feed body. Throws [org.json.JSONException] when the body is not a feed at all; tolerates missing optional fields. */
    fun parse(body: String): Feed {
        val o = JSONObject(body)
        val todayO = o.optJSONObject("today")
        val windowO = o.optJSONObject("window")
        val today = FeedToday(
            date = todayO?.let { Json.str(it, "date") } ?: "",
            planned = todayO?.optInt("planned", 0) ?: 0,
            done = todayO?.optInt("done", 0) ?: 0,
            overdueCount = todayO?.optInt("overdue_count", 0) ?: 0,
            top = Json.strings(todayO?.optJSONArray("top")),
            tasks = Json.objects(todayO?.optJSONArray("tasks")).mapNotNull { t ->
                val id = Json.str(t, "id") ?: return@mapNotNull null
                FeedTask(
                    id = id,
                    title = t.optString("title", ""),
                    done = t.optString("status", "open") == "done",
                    isTop = t.optBoolean("is_top", false),
                    durationMin = t.optInt("duration_min", 0),
                )
            },
            blocks = Json.objects(todayO?.optJSONArray("blocks")).mapNotNull { b ->
                val id = Json.str(b, "id") ?: return@mapNotNull null
                val start = Json.str(b, "start_time") ?: return@mapNotNull null
                FeedBlock(
                    id = id,
                    title = b.optString("title", ""),
                    startTime = start, // kept as sent: TimeBlock.of treats anything but "HH:mm" as "no block", i.e. fails open
                    endTime = Json.str(b, "end_time"),
                    durationMin = b.optInt("duration_min", 0),
                    done = b.optString("status", "open") == "done",
                )
            },
        )
        val window = FeedWindow(
            from = windowO?.let { Json.str(it, "from") } ?: today.date,
            to = windowO?.let { Json.str(it, "to") } ?: today.date,
            coveredUntil = windowO?.let { Json.str(it, "covered_until") ?: Json.str(it, "to") } ?: today.date,
            truncated = windowO?.optBoolean("truncated", false) ?: false,
        )
        val alarms = Json.objects(o.optJSONArray("alarms")).mapNotNull { a ->
            val taskId = Json.str(a, "task_id") ?: return@mapNotNull null
            val date = Json.str(a, "date") ?: return@mapNotNull null
            val time = Json.str(a, "time") ?: return@mapNotNull null
            FeedAlarm(
                taskId = taskId,
                date = date,
                time = time,
                title = a.optString("title", ""),
                kind = if (a.optString("kind", "notification") == "alarm") Kind.ALARM else Kind.NOTIFICATION,
                durationMin = a.optInt("duration_min", 0),
            )
        }
        return Feed(
            version = Json.str(o, "version") ?: "",
            serverTime = Json.str(o, "server_time") ?: "",
            timezone = Json.str(o, "timezone") ?: "UTC",
            today = today,
            window = window,
            alarms = alarms,
            settings = FeedSettings.fromJson(o.optJSONObject("settings")),
        )
    }
}
