package com.naveenraj.taskrelay

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import java.time.Instant
import java.time.ZoneId

/**
 * The app blocker. An AccessibilityService that listens for ONE event type, TYPE_WINDOW_STATE_CHANGED, and reads ONE thing from it:
 * the package name of the window that came to the front. It cannot read the screen (canRetrieveWindowContent=false), draw gestures
 * or see key presses, and beyond that one package-name check it does nothing while no app from the user's blocked list is in
 * front: no polling, no foreground service, no wake lock, no overlay permission.
 *
 * When a blocked-list app comes to the front, [BlockerPolicy] decides from the stored settings and today's cached numbers. If it
 * says "blocked", the block screen ([BlockerOverlay]) goes up FIRST so that no app content shows, and ~100 ms later the Home
 * action sends the user to the launcher. The screen stays until the user taps a button, 12 s pass, or another app comes to the
 * front. While a blocked-list app stays in front a 15 s heartbeat re-checks, because a task block can start under the user's
 * thumb; it stops the moment the user leaves, when the screen turns off, or when the blocker is switched off.
 *
 * The rest of the app calls [reevaluate] after anything that can change the answer (settings saved, a sync finished, a task
 * completed from a notification / widget / alarm screen). Missing or stale data never blocks (see BlockerPolicy: fail open).
 * Every callback is wrapped: nothing may throw out of an accessibility callback, and nothing about the user's apps or screen
 * is ever logged.
 */
class BlockerAccessibilityService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var overlay: BlockerOverlay? = null
    private var receiver: BroadcastReceiver? = null

    /** Package of the window the user is in, or null when unknown (just connected, or we just sent them home). */
    private var lastForeground: String? = null

    /** The app whose block screen is up. It can differ from [lastForeground]: the screen stays over the launcher. */
    private var overlayPkg: String? = null
    private var homeTarget: String? = null
    private var settlePkg: String? = null
    private var settleUntil = 0L
    private var checking = false

    private val keyboards = Cached(DEVICE_SETS_TTL_MS) { InstalledApps.keyboardPackages(this) }
    private val launchers = Cached(DEVICE_SETS_TTL_MS) { InstalledApps.homePackages(this) }
    private val protectedExtras = Cached(DEVICE_SETS_TTL_MS) { InstalledApps.protectedExtras(this) }

    private val heartbeat = Runnable { guarded("heartbeat") { recheck() } }
    private val goHome = Runnable { guarded("home") { performHome() } }
    private val autoDismiss = Runnable { guarded("auto dismiss") { dismissOverlay() } }

    private val screenActions = object : BlockerOverlay.Actions {
        override fun onOpenApp() = guarded("open app") { openTaskRelay() }
        override fun onCheckAgain() = guarded("check again") { checkAgain() }
        override fun onClose() = guarded("close") { dismissOverlay() }
    }

    // ── lifecycle ────────────────────────────────────────────────────────────────────────────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        guarded("connect") {
            instance = this
            if (overlay == null) overlay = BlockerOverlay(this, screenActions)
            if (receiver == null) registerScreenReceiver()
        }
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: Intent?): Boolean {
        guarded("unbind") { shutdown() }
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        guarded("destroy") { shutdown() }
        super.onDestroy()
    }

    private fun shutdown() {
        if (instance === this) instance = null
        handler.removeCallbacksAndMessages(null) // this service's own handler: safe to clear completely
        overlay?.dismiss()
        overlay = null
        overlayPkg = null
        lastForeground = null
        homeTarget = null
        checking = false
        receiver?.let { r ->
            try {
                unregisterReceiver(r)
            } catch (_: Throwable) {
            }
        }
        receiver = null
    }

    // ── events ───────────────────────────────────────────────────────────────────────────────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        guarded("event") { onWindowChanged(event) }
    }

    /** A window came to the front. Only its package name is read; nothing else about the event is looked at. */
    private fun onWindowChanged(event: AccessibilityEvent?) {
        if (event == null || event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (isNoise(pkg)) return
        if (pkg == settlePkg && SystemClock.elapsedRealtime() < settleUntil) return // the app we just sent home, still winding down
        lastForeground = pkg
        dismissIfUserMovedOn(pkg)
        val config = Stores.blockerStore(applicationContext).read()
        if (config.enabled && pkg in config.packages) evaluate(pkg, config) else handler.removeCallbacks(heartbeat)
    }

    /** Windows that say nothing about which app the user is in: no package, ourselves, the system UI, the system's own dialogs, keyboards. */
    private fun isNoise(pkg: String): Boolean = pkg == packageName || pkg == SYSTEM_UI || pkg == ANDROID || pkg in keyboards.get()

    /**
     * The block screen stays over the launcher; any OTHER app coming to the front (not that app, not a launcher) takes it down. Not
     * in the second after we sent the user Home either: the launcher's own events (and a launcher this device did not list) must not
     * take the screen down before anyone saw it.
     */
    private fun dismissIfUserMovedOn(pkg: String) {
        val shown = overlayPkg ?: return
        if (pkg == shown || SystemClock.elapsedRealtime() < settleUntil) return
        if (pkg !in launchers.get()) dismissOverlay()
    }

    // ── deciding ─────────────────────────────────────────────────────────────────────────────────────────────────

    /** Re-checks whatever is relevant now: the app whose block screen is up, else the app in front. */
    private fun recheck() {
        val target = overlayPkg ?: lastForeground ?: return
        val config = Stores.blockerStore(applicationContext).read()
        if (!config.enabled || target !in config.packages) {
            if (overlayPkg == target) dismissOverlay()
            if (lastForeground == target) handler.removeCallbacks(heartbeat)
            return
        }
        evaluate(target, config)
    }

    private fun evaluate(pkg: String, config: BlockerConfig) {
        val app = applicationContext
        if (InstalledApps.isProtected(pkg, protectedExtras.get())) { // whatever an old config says: never lock the user out
            if (overlayPkg == pkg) dismissOverlay()
            if (lastForeground == pkg) handler.removeCallbacks(heartbeat)
            return
        }
        val nowMs = System.currentTimeMillis()
        val zone = ZoneId.systemDefault()
        val today = Stores.todayCache(app).read()
        val decision = BlockerPolicy.decide(config, today, nowMs, zone)
        if (decision.code == BlockCode.NO_DATA) askForSync(app)
        if (decision.blocked) showBlock(pkg, decision, config, today) else if (overlayPkg == pkg) dismissOverlay()
        if (pkg == lastForeground) scheduleHeartbeat(decision, nowMs, zone)
    }

    /** The cache is yesterday's (or missing): fail open, but ask for fresh data, at most once every 5 minutes. */
    private fun askForSync(app: Context) {
        val now = SystemClock.elapsedRealtime()
        if (lastSyncAskAt != 0L && now - lastSyncAskAt < SYNC_ASK_EVERY_MS) return
        if (!SessionStore.isSignedIn(app)) return
        lastSyncAskAt = now
        SyncWorker.enqueueOnce(app)
    }

    // ── blocking ─────────────────────────────────────────────────────────────────────────────────────────────────

    private fun showBlock(pkg: String, d: BlockerPolicy.Decision, config: BlockerConfig, today: TodayData?) {
        val ov = overlay ?: return
        val fresh = !ov.isShowing || overlayPkg != pkg
        ov.show(BlockerText.screen(InstalledApps.label(applicationContext, pkg), d, config.unlockWhenDone, today, android.text.format.DateFormat.is24HourFormat(applicationContext)))
        overlayPkg = pkg
        val userIsInIt = pkg == lastForeground
        if (!checking && (fresh || userIsInIt)) armAutoDismiss() // while a check runs its end re-arms the timer
        if (userIsInIt) queueHome(pkg)
    }

    /** ~100 ms after the screen is up, so the user never sees the app's own content. One at a time. */
    private fun queueHome(pkg: String) {
        if (homeTarget != null) return
        homeTarget = pkg
        handler.postDelayed(goHome, HOME_DELAY_MS)
    }

    private fun performHome() {
        val target = homeTarget
        homeTarget = null
        if (target == null || target != lastForeground) return // the user already left
        if (performGlobalAction(GLOBAL_ACTION_HOME)) {
            // We sent them to the launcher: the app's late window events must not count as "the user is in it again".
            lastForeground = null
            settlePkg = target
            settleUntil = SystemClock.elapsedRealtime() + SETTLE_MS
            handler.removeCallbacks(heartbeat)
        } else {
            Log.w(TAG, "the home action was refused") // the heartbeat tries again
        }
    }

    private fun armAutoDismiss() {
        handler.removeCallbacks(autoDismiss)
        handler.postDelayed(autoDismiss, SCREEN_MS)
    }

    private fun dismissOverlay() {
        handler.removeCallbacks(autoDismiss)
        overlay?.dismiss()
        overlayPkg = null
        checking = false
    }

    // ── the block screen's buttons ───────────────────────────────────────────────────────────────────────────────

    private fun openTaskRelay() {
        try {
            startActivity(Notifications.openAppIntent(this, "blocker")) // started before the screen goes: it still counts as visible
        } catch (t: Throwable) {
            Log.w(TAG, "could not open the app: ${t.javaClass.simpleName}")
        }
        dismissOverlay()
    }

    /** One sync through the normal path (it also re-evaluates when it ends); "Checking..." and no auto-dismiss meanwhile. */
    private fun checkAgain() {
        if (checking) return
        checking = true
        handler.removeCallbacks(autoDismiss)
        overlay?.setStatus(null)
        overlay?.setChecking(true)
        val app = applicationContext
        Bg.io.execute {
            val ok = try {
                SyncClient(app).runOnce("blocker").ok
            } catch (t: Throwable) {
                false
            }
            handler.post { guarded("check done") { if (instance === this) onCheckDone(ok) } }
        }
    }

    private fun onCheckDone(ok: Boolean) {
        checking = false
        overlay?.setChecking(false)
        recheck() // dismisses the screen when nothing blocks any more, refreshes the numbers when something still does
        val ov = overlay ?: return
        if (ov.isShowing) {
            ov.setStatus(if (ok) BlockerText.CHECKED_UNCHANGED else BlockerText.CHECK_FAILED)
            armAutoDismiss()
        }
    }

    // ── heartbeat and screen state ───────────────────────────────────────────────────────────────────────────────

    /** Re-check in 15 s, or exactly when the next block / window starts or ends, whichever comes first. */
    private fun scheduleHeartbeat(d: BlockerPolicy.Decision, nowMs: Long, zone: ZoneId) {
        var delay = HEARTBEAT_MS
        d.nextChangeMin?.let { minute -> delay = minOf(delay, maxOf(MIN_TICK_MS, msUntilMinute(minute, nowMs, zone))) }
        handler.removeCallbacks(heartbeat)
        handler.postDelayed(heartbeat, delay)
    }

    private fun msUntilMinute(minute: Int, nowMs: Long, zone: ZoneId): Long {
        val intoDayMs = Instant.ofEpochMilli(nowMs).atZone(zone).toLocalTime().toNanoOfDay() / 1_000_000L
        return minute * 60_000L - intoDayMs + 50 // a hair after the boundary, so "now" has really crossed it
    }

    private fun registerScreenReceiver() {
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                guarded("screen") { onScreen(intent.action) }
            }
        }
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(r, filter) // system broadcasts only: no export flag needed
        receiver = r
    }

    private fun onScreen(action: String?) {
        when (action) {
            // Screen off: nothing to watch, nobody to show a screen to.
            Intent.ACTION_SCREEN_OFF -> {
                handler.removeCallbacks(heartbeat)
                dismissOverlay()
            }
            // Unlocked (or no lock screen): the app that was in front before is in front again.
            Intent.ACTION_USER_PRESENT -> recheck()
            Intent.ACTION_SCREEN_ON -> if (!keyguardLocked()) recheck()
        }
    }

    private fun keyguardLocked(): Boolean = (getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)?.isKeyguardLocked ?: false

    private inline fun guarded(what: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.w(TAG, "$what failed: ${t.javaClass.simpleName}") // the class only: never an app name, a title or screen content
        }
    }

    /** A value that is recomputed at most every [ttlMs]. Main thread only. */
    private class Cached<T : Any>(private val ttlMs: Long, private val load: () -> T) {
        private var value: T? = null
        private var at = 0L

        fun get(): T {
            val now = SystemClock.elapsedRealtime()
            val v = value
            if (v != null && now - at < ttlMs) return v
            return load().also {
                value = it
                at = now
            }
        }
    }

    companion object {
        private const val TAG = "BlockerService"
        private const val SYSTEM_UI = "com.android.systemui"
        private const val ANDROID = "android"
        private const val HEARTBEAT_MS = 15_000L
        private const val MIN_TICK_MS = 250L
        private const val HOME_DELAY_MS = 100L
        private const val SETTLE_MS = 1_000L
        private const val SCREEN_MS = 12_000L
        private const val SYNC_ASK_EVERY_MS = 5 * 60_000L
        private const val DEVICE_SETS_TTL_MS = 60_000L

        /** The connected service, or null (not enabled in system settings, or not yet bound). */
        @Volatile
        private var instance: BlockerAccessibilityService? = null

        @Volatile
        private var lastSyncAskAt = 0L

        /**
         * Re-checks the blocker NOW: call after anything that can change the answer (settings saved, a sync finished, a task
         * completed, sign-out). Safe from any thread; does nothing while the service is not running.
         */
        @Suppress("UNUSED_PARAMETER")
        fun reevaluate(app: Context) {
            val s = instance ?: return
            s.handler.post { s.guarded("reevaluate") { if (instance === s) s.recheck() } }
        }
    }
}
