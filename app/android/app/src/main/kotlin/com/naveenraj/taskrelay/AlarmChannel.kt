package com.naveenraj.taskrelay

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.time.ZoneId
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The one MethodChannel between Dart and the native layer: `com.naveenraj.taskrelay/native`. Results are plain maps / lists /
 * strings / bools / numbers. Long operations run off the main thread and reply when done.
 *
 * Dart -> native: getSession, setSession, clearSession, syncNow, requestSync, getSyncStatus, getPermissionStatus,
 *   requestNotificationPermission, openExactAlarmSettings, openFullScreenIntentSettings, openNotificationSettings, getTimeZone,
 *   getAppVersion, getInitialShare, getLaunchAction, refreshWidget.
 * native -> Dart (via [DartBridge], only while the engine exists): onShare, onActionsChanged, onSyncFinished.
 */
class AlarmChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val app = activity.applicationContext
    private val channel = MethodChannel(messenger, NAME)
    private val syncExecutor = Executors.newSingleThreadExecutor { r -> Thread(r, "taskrelay-sync").apply { isDaemon = true } }
    private val notificationWaiters = mutableListOf<MethodChannel.Result>()

    fun register() {
        channel.setMethodCallHandler(this)
        DartBridge.attach(channel)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        DartBridge.detach(channel)
        syncExecutor.shutdown()
        val waiters = notificationWaiters.toList()
        notificationWaiters.clear()
        for (w in waiters) reply { w.success(false) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getSession" -> async(result) {
                    SessionStore.get(app)?.let { mapOf("baseUrl" to it.baseUrl, "token" to it.token) }
                }

                "setSession" -> {
                    val baseUrl = call.argument<String>("baseUrl")?.trim()
                    val token = call.argument<String>("token")
                    if (baseUrl.isNullOrEmpty() || token.isNullOrEmpty() || !isHttpUrl(baseUrl)) {
                        result.error("invalid_argument", "baseUrl (http/https) and token are required", null)
                        return
                    }
                    async(result) {
                        SessionStore.set(app, baseUrl, token)
                        // a fresh sign-in clears a stale "session expired" flag
                        Stores.alarmStore(app).update { if (it.lastErrorCode == "unauthorized") it.copy(lastError = null, lastErrorCode = null) else it }
                        Notifications.ensureChannels(app)
                        SyncWorker.schedulePeriodic(app)
                        SyncWorker.enqueueOnce(app)
                        TodayWidgetProvider.refreshAll(app)
                        true
                    }
                }

                "clearSession" -> async(result) {
                    clearSession()
                    true
                }

                "syncNow" -> syncNow(result)

                "requestSync" -> {
                    SyncWorker.enqueueOnce(app)
                    result.success(true)
                }

                "getSyncStatus" -> async(result) { syncStatus() }

                "getPermissionStatus" -> result.success(
                    mapOf(
                        "notifications" to Permissions.notificationsAllowed(app),
                        "exactAlarm" to Permissions.exactAlarmAllowed(app),
                        "fullScreenIntent" to Permissions.fullScreenIntentAllowed(app),
                    ),
                )

                "requestNotificationPermission" -> requestNotificationPermission(result)

                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        open(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri()), appDetails())
                    }
                    result.success(true)
                }

                "openFullScreenIntentSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        open(Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, packageUri()), appDetails())
                    }
                    result.success(true)
                }

                "openNotificationSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, app.packageName)
                    } else {
                        appDetails()
                    }
                    open(intent, appDetails())
                    result.success(true)
                }

                "getTimeZone" -> result.success(ZoneId.systemDefault().id)
                "getAppVersion" -> result.success(AppInfo.versionName(app))
                "getInitialShare" -> result.success(LaunchState.takeShare()?.toMap())
                "getLaunchAction" -> result.success(LaunchState.takeAction())

                "refreshWidget" -> {
                    TodayWidgetProvider.refreshAll(app)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(TAG, "${call.method} failed: ${t.javaClass.simpleName}")
            reply { result.error("native_error", t.message ?: t.javaClass.simpleName, null) }
        }
    }

    /** Called from MainActivity.onRequestPermissionsResult. */
    fun onPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_NOTIFICATIONS) return
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        val waiters = notificationWaiters.toList()
        notificationWaiters.clear()
        for (w in waiters) reply { w.success(granted) }
    }

    // ── operations ───────────────────────────────────────────────────────────────────────────────────────────────

    /** Full SyncClient.runOnce on a background thread; replies when it finishes, or with a `network` error after 30 s. */
    private fun syncNow(result: MethodChannel.Result) {
        val replied = AtomicBoolean(false)
        fun finish(r: SyncResult) {
            if (replied.compareAndSet(false, true)) reply { result.success(r.toMap()) }
        }
        val timeout = Runnable {
            finish(SyncResult(ok = false, error = "The sync took too long", errorCode = "network", syncedAtMs = Stores.alarmStore(app).read().lastSyncMs ?: 0L))
        }
        Bg.main.postDelayed(timeout, SYNC_TIMEOUT_MS)
        try {
            syncExecutor.execute {
                val r = try {
                    SyncClient(app).runOnce("foreground")
                } catch (t: Throwable) {
                    SyncResult(ok = false, error = "Unexpected error (${t.javaClass.simpleName})", errorCode = "server")
                }
                Bg.main.removeCallbacks(timeout)
                finish(r)
            }
        } catch (t: Throwable) {
            Bg.main.removeCallbacks(timeout)
            finish(SyncResult(ok = false, error = "Sync unavailable", errorCode = "server"))
        }
    }

    private fun syncStatus(): Map<String, Any?> {
        val now = System.currentTimeMillis()
        val st = Stores.alarmStore(app).read()
        val signedIn = SessionStore.isSignedIn(app)
        val next = st.entries.filter { Kind.isTaskKind(it.kind) && it.triggerMs > now }.minOfOrNull { it.triggerMs }
        return mapOf(
            "signedIn" to signedIn,
            "lastSyncMs" to st.lastSyncMs,
            "armedCount" to st.armedCount,
            "armedThrough" to st.armedThrough,
            "nextAlarmMs" to next,
            "pendingActions" to Stores.actionLog(app).count(),
            "lastError" to st.lastError,
            "lastErrorCode" to st.lastErrorCode,
            "exactAlarmAllowed" to Permissions.exactAlarmAllowed(app),
            "notificationsAllowed" to Permissions.notificationsAllowed(app),
            "fullScreenIntentAllowed" to Permissions.fullScreenIntentAllowed(app),
        )
    }

    /**
     * Sign-out: no work, alarm, reminder, snooze, notification, log line or cached task may survive. Waits (briefly) for an
     * in-flight sync so it cannot re-arm alarms after they were wiped; the session goes first, so a later run does nothing.
     */
    private fun clearSession() {
        val locked = try {
            SyncClient.SYNC_LOCK.tryLock(15, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            false
        }
        try {
            SessionStore.clear(app)
            SyncWorker.cancelAll(app)
            AlarmService.stopIfRinging(null)
            AlarmScheduler.cancelAll(app) // every armed alarm / reminder / snooze, and the AlarmStore
            Stores.actionLog(app).clear()
            Stores.todayCache(app).clear()
            Notifications.cancelAll(app)
            TodayWidgetProvider.refreshAll(app) // signed-out state
        } finally {
            if (locked) SyncClient.SYNC_LOCK.unlock()
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        val first = notificationWaiters.isEmpty()
        notificationWaiters.add(result) // answered from onPermissionsResult, i.e. after the user chose
        if (first) activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFICATIONS)
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────────────────────────────

    /** Runs [block] on the background executor and replies on the main thread. */
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        Bg.io.execute {
            val value: Any? = try {
                block()
            } catch (t: Throwable) {
                Log.e(TAG, "async call failed: ${t.javaClass.simpleName}")
                reply { result.error("native_error", t.message ?: t.javaClass.simpleName, null) }
                return@execute
            }
            reply { result.success(value) }
        }
    }

    /** MethodChannel replies belong on the main thread; a reply to a destroyed engine must never crash us. */
    private fun reply(block: () -> Unit) {
        Bg.main.post {
            try {
                block()
            } catch (t: Throwable) {
                Log.w(TAG, "reply dropped: ${t.javaClass.simpleName}")
            }
        }
    }

    private fun open(intent: Intent, fallback: Intent) {
        try {
            activity.startActivity(intent)
        } catch (_: Throwable) {
            try {
                activity.startActivity(fallback)
            } catch (t: Throwable) {
                Log.w(TAG, "no settings screen available: ${t.javaClass.simpleName}")
            }
        }
    }

    private fun packageUri(): Uri = Uri.parse("package:${app.packageName}")

    private fun appDetails(): Intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri())

    private fun isHttpUrl(s: String): Boolean = try {
        val u = URI(s)
        (u.scheme == "http" || u.scheme == "https") && !u.host.isNullOrEmpty()
    } catch (_: Exception) {
        false
    }

    companion object {
        const val NAME = "com.naveenraj.taskrelay/native"
        private const val TAG = "AlarmChannel"
        private const val REQ_NOTIFICATIONS = 7411
        private const val SYNC_TIMEOUT_MS = 30_000L
    }
}
