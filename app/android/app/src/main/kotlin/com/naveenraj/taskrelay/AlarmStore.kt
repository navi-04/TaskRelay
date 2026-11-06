package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Everything the native layer persists about the schedule and the sync. One JSON file; see [AlarmStore]. */
data class StoreState(
    /** Planned entries (up to 400); only the nearest 100 future ones are armed with AlarmManager. */
    val entries: List<Entry> = emptyList(),
    val feedEtag: String? = null,
    /** `server_time` of the last applied feed: an older feed (worker vs foreground race) is ignored. */
    val feedAsOfMs: Long = 0L,
    val coveredUntil: String? = null,
    val settings: FeedSettings? = null,
    /** The timezone the server last reported for this user. */
    val serverTimezone: String? = null,
    /** The device zone we last PATCHed (success or a permanent rejection): "once per difference". */
    val lastPatchedTimezone: String? = null,
    val armedThrough: String? = null,
    val armedCount: Int = 0,
    val nextAlarmMs: Long? = null,
    val lastSyncMs: Long? = null,
    val lastError: String? = null,
    val lastErrorCode: String? = null,
    val exactAlarmAllowed: Boolean = true,
    /** App versionName for which the server answered 426: no sync is attempted until the app version changes. */
    val upgradeRequiredVersion: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("v", 1)
        put("entries", JSONArray().also { a -> entries.forEach { a.put(it.toJson()) } })
        put("feedEtag", feedEtag ?: JSONObject.NULL)
        put("feedAsOfMs", feedAsOfMs)
        put("coveredUntil", coveredUntil ?: JSONObject.NULL)
        put("settings", settings?.toJson() ?: JSONObject.NULL)
        put("serverTimezone", serverTimezone ?: JSONObject.NULL)
        put("lastPatchedTimezone", lastPatchedTimezone ?: JSONObject.NULL)
        put("armedThrough", armedThrough ?: JSONObject.NULL)
        put("armedCount", armedCount)
        put("nextAlarmMs", nextAlarmMs ?: JSONObject.NULL)
        put("lastSyncMs", lastSyncMs ?: JSONObject.NULL)
        put("lastError", lastError ?: JSONObject.NULL)
        put("lastErrorCode", lastErrorCode ?: JSONObject.NULL)
        put("exactAlarmAllowed", exactAlarmAllowed)
        put("upgradeRequiredVersion", upgradeRequiredVersion ?: JSONObject.NULL)
    }

    companion object {
        fun fromJson(o: JSONObject): StoreState = StoreState(
            entries = Json.objects(o.optJSONArray("entries")).mapNotNull { Entry.fromJson(it) },
            feedEtag = Json.str(o, "feedEtag"),
            feedAsOfMs = o.optLong("feedAsOfMs", 0L),
            coveredUntil = Json.str(o, "coveredUntil"),
            settings = o.optJSONObject("settings")?.let { FeedSettings.fromJson(it) },
            serverTimezone = Json.str(o, "serverTimezone"),
            lastPatchedTimezone = Json.str(o, "lastPatchedTimezone"),
            armedThrough = Json.str(o, "armedThrough"),
            armedCount = o.optInt("armedCount", 0),
            nextAlarmMs = if (o.isNull("nextAlarmMs")) null else o.optLong("nextAlarmMs"),
            lastSyncMs = if (o.isNull("lastSyncMs")) null else o.optLong("lastSyncMs"),
            lastError = Json.str(o, "lastError"),
            lastErrorCode = Json.str(o, "lastErrorCode"),
            exactAlarmAllowed = o.optBoolean("exactAlarmAllowed", true),
            upgradeRequiredVersion = Json.str(o, "upgradeRequiredVersion"),
        )
    }
}

/**
 * The schedule + sync state as a JSON file in filesDir (replaced atomically). All access goes through [LOCK], which is the same
 * process-wide lock AlarmScheduler uses, so a read-modify-write is never interleaved with another one.
 */
class AlarmStore(private val file: File) {

    fun read(): StoreState = synchronized(LOCK) { readUnlocked() }

    /** Atomic read-modify-write. */
    fun update(block: (StoreState) -> StoreState): StoreState = synchronized(LOCK) {
        val next = block(readUnlocked())
        AtomicFiles.write(file, next.toJson().toString().toByteArray(Charsets.UTF_8))
        next
    }

    fun clear() {
        synchronized(LOCK) { file.delete() }
    }

    private fun readUnlocked(): StoreState {
        val text = AtomicFiles.readText(file) ?: return StoreState()
        return try {
            StoreState.fromJson(JSONObject(text))
        } catch (_: Exception) {
            StoreState() // corrupt file: start clean, the next sync rebuilds it
        }
    }

    companion object {
        /** Process-wide lock shared by the store and AlarmScheduler (replaceAll / rearmFromStore / cancelAll). */
        val LOCK = Any()
    }
}
