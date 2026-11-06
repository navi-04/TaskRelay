package com.naveenraj.taskrelay

import org.json.JSONObject

/** The kinds of entries the native scheduler owns. */
object Kind {
    const val ALARM = "alarm"
    const val NOTIFICATION = "notification"
    const val REMINDER_DAILY = "reminder_daily"
    const val REMINDER_EOD = "reminder_eod"

    /** A 00:01 local trigger each day: light sync + widget refresh. Never visible to the user. */
    const val MIDNIGHT = "midnight"

    /** Native-owned: created by the Snooze action, never sent to the server. */
    const val SNOOZE = "snooze"

    /** Entries that belong to a task (they can be completed / snoozed and are what the app calls "alarms"). */
    fun isTaskKind(kind: String): Boolean = kind == ALARM || kind == NOTIFICATION || kind == SNOOZE
}

/**
 * One scheduled trigger.
 *
 * key = `<kind>/<taskId or '-'>/<date>[/<hhmm for snooze>]`
 * `date` is the task's date (yyyy-MM-dd); `localTime` is HH:mm wall-clock time in the device zone, so the instant can be
 * re-resolved after a timezone change. For `snooze` the trigger is an absolute instant (`localTime` is only informative)
 * and [origKind] says whether it was an alarm or a notification.
 */
data class Entry(
    val key: String,
    val kind: String,
    val taskId: String?,
    val date: String,
    val localTime: String,
    val title: String,
    val triggerMs: Long,
    val origKind: String? = null,
) {
    /** What actually happens when this entry fires: a snooze behaves like the kind it was created from. */
    val ringKind: String
        get() = if (kind == Kind.SNOOZE) (origKind ?: Kind.NOTIFICATION) else kind

    fun toJson(): JSONObject = JSONObject().apply {
        put("key", key)
        put("kind", kind)
        put("taskId", taskId ?: JSONObject.NULL)
        put("date", date)
        put("localTime", localTime)
        put("title", title)
        put("triggerMs", triggerMs)
        put("origKind", origKind ?: JSONObject.NULL)
    }

    companion object {
        fun keyFor(kind: String, taskId: String?, date: String, hhmm: String? = null): String =
            "$kind/${taskId ?: "-"}/$date" + (if (hhmm != null) "/$hhmm" else "")

        fun fromJson(o: JSONObject): Entry? {
            val key = o.optString("key", "")
            val kind = o.optString("kind", "")
            if (key.isEmpty() || kind.isEmpty()) return null
            return Entry(
                key = key,
                kind = kind,
                taskId = if (o.isNull("taskId")) null else o.optString("taskId").ifEmpty { null },
                date = o.optString("date", ""),
                localTime = o.optString("localTime", ""),
                title = o.optString("title", ""),
                triggerMs = o.optLong("triggerMs", 0L),
                origKind = if (o.isNull("origKind")) null else o.optString("origKind").ifEmpty { null },
            )
        }

        /** Best effort reconstruction from `kind/taskId/date[/hhmm]` when an Intent carries no extras. */
        fun fromKey(key: String): Entry? {
            val p = key.split('/')
            if (p.size < 3) return null
            return Entry(
                key = key,
                kind = p[0],
                taskId = p[1].takeIf { it != "-" },
                date = p[2],
                localTime = p.getOrNull(3)?.let { if (it.length == 4) it.substring(0, 2) + ":" + it.substring(2) else it } ?: "",
                title = "Reminder",
                triggerMs = 0L,
                origKind = if (p[0] == Kind.SNOOZE) Kind.NOTIFICATION else null,
            )
        }
    }
}

/** Intent extra names shared by the receivers, the service, the activity and the notification actions. */
object Extras {
    const val KEY = "key"
    const val KIND = "kind"
    const val TASK_ID = "taskId"
    const val DATE = "date"
    const val LOCAL_TIME = "localTime"
    const val TITLE = "title"
    const val TRIGGER_MS = "triggerMs"
    const val ORIG_KIND = "origKind"
}
