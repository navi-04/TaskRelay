package com.naveenraj.taskrelay

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.time.ZoneId
import java.util.concurrent.locks.ReentrantLock

/** Outcome of one sync run. errorCode: unauthorized | upgrade_required | rate_limited | network | server | not_signed_in. */
data class SyncResult(
    val ok: Boolean,
    val notModified: Boolean = false,
    val error: String? = null,
    val errorCode: String? = null,
    val armedCount: Int = 0,
    val armedThrough: String? = null,
    val syncedAtMs: Long = 0L,
    /** Worker hint: try again with backoff (network / 5xx / unreplayed log lines). Not part of the channel reply. */
    val retryable: Boolean = false,
    val retryAfterSec: Long? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "ok" to ok,
        "notModified" to notModified,
        "error" to error,
        "errorCode" to errorCode,
        "armedCount" to armedCount,
        "armedThrough" to armedThrough,
        "syncedAtMs" to syncedAtMs,
    )
}

/**
 * One full sync, shared by the WorkManager worker and the foreground `syncNow`, serialised by [SYNC_LOCK]:
 *
 *  1. replay every ActionLog line (PUT .../tasks/{id}/days/{date}; ack per ReplayPolicy)
 *  2. PATCH /me timezone when the device zone differs from the server's (before the feed, once per difference)
 *  3. GET /sync?days=14 with If-None-Match
 *  4. on 200 / 304: plan -> AlarmScheduler.replaceAll -> TodayCache (+ pending overlay) -> etag / settings / lastSyncMs -> widget
 *  5. report (onSyncFinished to Dart when the engine is alive)
 */
class SyncClient(context: Context, private val http: HttpTransport = UrlConnectionTransport) {
    private val app: Context = context.applicationContext
    private val store = Stores.alarmStore(app)
    private val log = Stores.actionLog(app)

    fun runOnce(trigger: String): SyncResult {
        SYNC_LOCK.lock()
        val result = try {
            doRun(trigger)
        } catch (t: Throwable) {
            Log.e(TAG, "sync crashed: ${t.javaClass.simpleName}")
            fail("server", "Unexpected error (${t.javaClass.simpleName})", retryable = true)
        } finally {
            SYNC_LOCK.unlock()
        }
        if (!result.ok && result.errorCode != "not_signed_in") {
            try {
                AlarmScheduler.rearmFromStore(app) // a failed sync must still top the armed set up
            } catch (_: Throwable) {
            }
        }
        DartBridge.syncFinished(result.ok, result.errorCode)
        return result
    }

    private fun doRun(trigger: String): SyncResult {
        Log.d(TAG, "sync started ($trigger)")
        val session = SessionStore.get(app)
            ?: return SyncResult(ok = false, error = "Not signed in", errorCode = "not_signed_in")
        val version = AppInfo.versionName(app)
        if (store.read().upgradeRequiredVersion == version) {
            return fail("upgrade_required", "Please update TaskRelay to continue", retryable = false)
        }
        val base = session.baseUrl.trimEnd('/')
        val headers = mapOf(
            "Authorization" to "Bearer ${session.token}",
            "X-App-Version" to version,
            "User-Agent" to "TaskRelay-Android/$version",
            "Accept" to "application/json",
        )

        // 1. replay the action log
        var needsRetry = false
        val lines = log.peek()
        for ((i, line) in lines.withIndex()) {
            if (i >= MAX_REPLAY_PER_RUN) {
                needsRetry = true
                break
            }
            val rec = ActionLog.parse(line)
            if (rec == null) {
                log.ack(listOf(line)) // malformed line: nothing can ever replay it
                continue
            }
            val (action, res) = replayOne(base, headers, rec)
            when (action) {
                ReplayAction.ACK -> log.ack(listOf(line))
                ReplayAction.STOP_KEEP -> return fail("unauthorized", "Your session expired. Sign in again.", retryable = false)
                ReplayAction.STOP_ALL -> {
                    store.update { it.copy(upgradeRequiredVersion = version) }
                    return fail("upgrade_required", "Please update TaskRelay to continue", retryable = false)
                }
                ReplayAction.KEEP_RETRY_LATER ->
                    return fail("rate_limited", "Too many requests. Trying again later.", retryable = false, retryAfterSec = res.retryAfterSec ?: DEFAULT_RETRY_AFTER_SEC)
                ReplayAction.KEEP_RETRY, ReplayAction.RETRY_WITHOUT_TIME -> {
                    if (res.isIoError) return fail("network", "No connection to the server", retryable = true)
                    needsRetry = true // 5xx: keep the line, try the others, retry the whole run later
                }
            }
        }

        // 2. timezone: make the server's "today" match the phone, once per difference, BEFORE reading the feed
        val zone = ZoneId.systemDefault().id
        val st0 = store.read()
        var dropEtag = false
        if (zone != st0.serverTimezone && zone != st0.lastPatchedTimezone) {
            val res = http.execute("PATCH", "$base/api/v1/me", headers, JSONObject().put("timezone", zone).toString())
            when {
                res.isIoError -> Unit // the feed request below will fail the same way and report it
                res.status in 200..299 -> {
                    store.update { it.copy(lastPatchedTimezone = zone, serverTimezone = zone, feedEtag = null) }
                    dropEtag = true
                }
                res.status == 401 -> return fail("unauthorized", "Your session expired. Sign in again.", retryable = false)
                res.status == 426 -> {
                    store.update { it.copy(upgradeRequiredVersion = version) }
                    return fail("upgrade_required", "Please update TaskRelay to continue", retryable = false)
                }
                res.status == 429 -> return fail("rate_limited", "Too many requests. Trying again later.", retryable = false, retryAfterSec = res.retryAfterSec ?: DEFAULT_RETRY_AFTER_SEC)
                res.status in 400..499 -> store.update { it.copy(lastPatchedTimezone = zone) } // rejected for good: do not retry until the zone changes
                else -> Unit // 5xx: try again on the next run
            }
        }

        // 3. the feed
        val etag = if (dropEtag) null else store.read().feedEtag
        val getHeaders = if (etag != null) headers + ("If-None-Match" to etag) else headers
        val res = http.execute("GET", "$base/api/v1/sync?days=$FEED_DAYS", getHeaders, null)
        return when {
            res.isIoError -> fail("network", "No connection to the server", retryable = true)
            res.status == 304 -> applyNotModified(needsRetry)
            res.status in 200..299 -> {
                val feed = try {
                    FeedParser.parse(res.body)
                } catch (_: Exception) {
                    return fail("server", "The server sent an unreadable response", retryable = true)
                }
                applyFeed(feed, res.headers["etag"] ?: feed.version.ifEmpty { null }, needsRetry)
            }
            res.status == 401 -> fail("unauthorized", "Your session expired. Sign in again.", retryable = false)
            res.status == 426 -> {
                store.update { it.copy(upgradeRequiredVersion = version) }
                fail("upgrade_required", "Please update TaskRelay to continue", retryable = false)
            }
            res.status == 429 -> fail("rate_limited", "Too many requests. Trying again later.", retryable = false, retryAfterSec = res.retryAfterSec ?: DEFAULT_RETRY_AFTER_SEC)
            res.status >= 500 -> fail("server", res.errorMessage ?: "Server error (HTTP ${res.status})", retryable = true)
            else -> fail("server", res.errorMessage ?: "Unexpected response (HTTP ${res.status})", retryable = false)
        }
    }

    // ── replay ───────────────────────────────────────────────────────────────────────────────────────────────────

    private fun replayOne(base: String, headers: Map<String, String>, rec: ActionLog.Record): Pair<ReplayAction, HttpResponse> {
        val url = "$base/api/v1/tasks/${rec.taskId}/days/${rec.date}"
        val withTime = JSONObject().put("status", "done").put("completed_at", java.time.Instant.ofEpochMilli(rec.tapMs).toString()).toString()
        var res = http.execute("PUT", url, headers, withTime)
        var action = ReplayPolicy.decide(res.status, res.errorCode, res.isIoError, timeSent = true)
        if (action == ReplayAction.RETRY_WITHOUT_TIME) {
            // The phone clock is ahead of the server's: record the completion without the tap time (once).
            res = http.execute("PUT", url, headers, JSONObject().put("status", "done").toString())
            action = ReplayPolicy.decide(res.status, res.errorCode, res.isIoError, timeSent = false)
        }
        return action to res
    }

    // ── apply ────────────────────────────────────────────────────────────────────────────────────────────────────

    private fun applyFeed(feed: Feed, etag: String?, needsRetry: Boolean): SyncResult {
        val now = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val asOf = feed.serverTimeMs ?: now

        // A feed older than the one already applied (a race between the worker and a foreground sync) must not roll things back.
        if (asOf < store.read().feedAsOfMs) {
            Log.w(TAG, "ignoring a feed older than the applied one")
            return applyNotModified(needsRetry)
        }

        // plan + replaceAll under the scheduler lock, reading the pending completes INSIDE it: a Complete tapped meanwhile either
        // shows up here, or its removeTaskDay() runs right after.
        synchronized(AlarmStore.LOCK) {
            val cur = store.read()
            val planned = FeedPlanner.plan(
                feed = feed,
                nowMs = now,
                zone = zone,
                pendingCompletes = log.pendingCompletes(),
                existingSnoozes = cur.entries.filter { it.kind == Kind.SNOOZE },
                carryOver = cur.entries,
            )
            AlarmScheduler.replaceAll(app, planned, now)
        }
        Stores.todayCache(app).writeFeed(feed.today, now) { log.pendingCompletes() }
        val st = store.update {
            it.copy(
                feedEtag = etag,
                feedAsOfMs = asOf,
                coveredUntil = feed.window.coveredUntil,
                settings = feed.settings,
                serverTimezone = feed.timezone,
                lastSyncMs = now,
                lastError = null,
                lastErrorCode = null,
            )
        }
        TodayWidgetProvider.refreshAll(app)
        return SyncResult(ok = true, notModified = false, armedCount = st.armedCount, armedThrough = st.armedThrough, syncedAtMs = now, retryable = needsRetry)
    }

    /** 304 (or a stale feed): nothing changed on the server. Re-plan from the store, which also tops the reminder horizon up. */
    private fun applyNotModified(needsRetry: Boolean): SyncResult {
        val now = System.currentTimeMillis()
        synchronized(AlarmStore.LOCK) {
            val cur = store.read()
            val planned = FeedPlanner.replan(cur.entries, cur.settings, now, ZoneId.systemDefault(), log.pendingCompletes())
            AlarmScheduler.replaceAll(app, planned, now)
        }
        val st = store.update { it.copy(lastSyncMs = now, lastError = null, lastErrorCode = null) }
        TodayWidgetProvider.refreshAll(app)
        return SyncResult(ok = true, notModified = true, armedCount = st.armedCount, armedThrough = st.armedThrough, syncedAtMs = now, retryable = needsRetry)
    }

    private fun fail(code: String, message: String, retryable: Boolean, retryAfterSec: Long? = null): SyncResult {
        val st = store.update { it.copy(lastError = message, lastErrorCode = code) }
        return SyncResult(
            ok = false,
            error = message,
            errorCode = code,
            armedCount = st.armedCount,
            armedThrough = st.armedThrough,
            syncedAtMs = st.lastSyncMs ?: 0L,
            retryable = retryable,
            retryAfterSec = retryAfterSec,
        )
    }

    companion object {
        private const val TAG = "SyncClient"
        private const val FEED_DAYS = 14
        private const val MAX_REPLAY_PER_RUN = 100
        private const val DEFAULT_RETRY_AFTER_SEC = 60L

        /** One sync at a time, process-wide: the WorkManager worker and the foreground syncNow share it. */
        val SYNC_LOCK = ReentrantLock()
    }
}
