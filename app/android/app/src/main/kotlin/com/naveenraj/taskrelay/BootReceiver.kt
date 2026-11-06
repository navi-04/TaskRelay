package com.naveenraj.taskrelay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.time.ZoneId
import java.util.TimeZone

/**
 * Re-arms everything after the system wiped or invalidated our registrations: BOOT_COMPLETED, MY_PACKAGE_REPLACED, TIME_SET,
 * TIMEZONE_CHANGED and SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED.
 *
 * It NEVER starts AlarmService: Android 15 forbids starting a mediaPlayback foreground service from BOOT_COMPLETED. Anything that
 * should have rung while the device was off is reported as a plain "Missed: <title>" notification instead.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val action = intent.action ?: return
        val zoneExtra = intent.getStringExtra("time-zone") // ACTION_TIMEZONE_CHANGED carries the new IANA id
        val pending = goAsync()
        Bg.io.execute {
            try {
                handle(app, action, zoneExtra)
            } catch (t: Throwable) {
                Log.e(TAG, "boot handling failed: ${t.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }

    private fun handle(app: Context, action: String, zoneExtra: String?) {
        if (!SessionStore.isSignedIn(app)) return
        val now = System.currentTimeMillis()

        // 1. wall-clock entries are re-resolved to instants in the (new) zone
        if (action == Intent.ACTION_TIME_CHANGED || action == Intent.ACTION_TIMEZONE_CHANGED) {
            if (action == Intent.ACTION_TIMEZONE_CHANGED) TimeZone.setDefault(null) // drop the cached default zone
            val zone = zoneExtra?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: ZoneId.systemDefault()
            AlarmScheduler.reResolve(app, zone, now)
        }

        // 2. what passed while we were off (within the last 6 hours): a plain "Missed" notification, then forget it
        for (e in AlarmScheduler.takeMissed(app, now)) {
            val id = e.taskId
            if (id != null && Stores.actionLog(app).hasComplete(id, e.date)) continue
            Notifications.postMissed(app, e.key, e.title)
        }

        // 3. everything the OS forgot is armed again (nearest 100), and the background sync is guaranteed to be scheduled
        AlarmScheduler.rearmFromStore(app, force = true, nowMs = now)
        SyncWorker.schedulePeriodic(app)
        SyncWorker.enqueueOnce(app)
        TodayWidgetProvider.refreshAll(app)
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
