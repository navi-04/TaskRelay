package com.naveenraj.taskrelay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import java.time.ZoneId

/**
 * Fired by AlarmManager for every entry (the PendingIntent carries the whole entry, so a re-plan racing with the fire cannot
 * lose it). Branches on the entry kind, then ALWAYS re-arms from the store (top-up) and forgets the entry that just fired.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val e = Entry.fromIntent(intent) ?: return
        try {
            dispatch(app, e)
        } catch (t: Throwable) {
            Log.e(TAG, "dispatch failed for ${e.kind}: ${t.javaClass.simpleName}")
        }
        // Housekeeping off the main thread: drop the fired entry and top the armed set up.
        val pending = goAsync()
        Bg.io.execute {
            try {
                AlarmScheduler.markFired(app, e.key)
            } catch (t: Throwable) {
                Log.e(TAG, "rearm failed: ${t.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }

    private fun dispatch(app: Context, e: Entry) {
        if (!SessionStore.isSignedIn(app)) return // signed out: a stale registration must stay silent
        val taskId = e.taskId
        if (Kind.isTaskKind(e.kind) && taskId != null && Stores.actionLog(app).hasComplete(taskId, e.date)) return // completed meanwhile

        when (e.kind) {
            Kind.ALARM -> ring(app, e)
            Kind.NOTIFICATION -> Notifications.postTask(app, e)
            Kind.SNOOZE -> if (e.ringKind == Kind.ALARM) ring(app, e) else Notifications.postTask(app, e)
            Kind.REMINDER_DAILY -> {
                val text = ReminderText.daily(Stores.todayCache(app).read(), today(), carryOver(app))
                Notifications.postReminder(app, e.key, text.title, text.body)
            }
            Kind.REMINDER_EOD -> {
                val text = ReminderText.endOfDay(Stores.todayCache(app).read(), today())
                Notifications.postReminder(app, e.key, text.title, text.body)
            }
            Kind.MIDNIGHT -> {
                SyncWorker.enqueueOnce(app)
                TodayWidgetProvider.refreshAll(app)
            }
            else -> Log.w(TAG, "unknown entry kind ${e.kind}")
        }
    }

    /**
     * Rings through AlarmService. If the foreground service cannot be started (background-start restrictions) the full-screen-intent
     * heads-up notification takes over: its channel plays the alarm sound.
     */
    private fun ring(app: Context, e: Entry) {
        try {
            val svc = e.putExtras(Intent(app, AlarmService::class.java).setAction(AlarmService.ACTION_START_ALARM))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(svc) else app.startService(svc)
        } catch (t: Throwable) {
            Log.w(TAG, "AlarmService start refused (${t.javaClass.simpleName}); posting the full-screen heads-up instead")
            Notifications.postRingFallback(app, e)
        }
    }

    private fun today(): String = java.time.LocalDate.now(ZoneId.systemDefault()).toString()

    private fun carryOver(app: Context): Boolean = Stores.alarmStore(app).read().settings?.carryOverAlerts ?: true

    companion object {
        private const val TAG = "AlarmReceiver"
    }
}
