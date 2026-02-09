package com.example.sampleapp

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * BroadcastReceiver triggered by AlarmManager.setAlarmClock().
 *
 * Starts AlarmService which handles EVERYTHING:
 *   - Posts notification with fullScreenIntent (shows Activity on lock screen)
 *   - Shows overlay window (for unlocked screen)
 *   - Plays alarm sound + vibration
 *
 * IMPORTANT: We do NOT acquire wake lock here. If we wake the screen
 * before the notification fires, Android treats the device as "in use"
 * and won't trigger the full-screen intent — breaking lock screen display.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🚨🚨🚨 ALARM TRIGGERED! 🚨🚨🚨")

        val taskTitle = intent.getStringExtra("taskTitle") ?: "Task Reminder"
        val notificationId = intent.getIntExtra("notificationId", 0)
        Log.d(TAG, "  Task: $taskTitle, ID: $notificationId")

        // ── IMPORTANT: Do NOT acquire wake lock here! ────────────────
        // If we turn the screen on now, Android thinks the device is
        // "in use" and will NOT trigger the notification's full-screen
        // intent. The full-screen intent is the ONLY reliable way to
        // show AlarmActivity over the lock screen on OnePlus/ColorOS.
        // The service will handle screen wake AFTER the notification
        // full-screen intent has had a chance to fire.

        // ── Start AlarmService — it handles everything ───────────────
        try {
            val svcIntent = Intent(context, AlarmService::class.java).apply {
                action = AlarmService.ACTION_START_ALARM
                putExtra("taskTitle", taskTitle)
                putExtra("notificationId", notificationId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(svcIntent)
            } else {
                context.startService(svcIntent)
            }
            Log.d(TAG, "✅ AlarmService started — it will handle UI, sound, vibration")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Service start failed: ${e.message}", e)
        }
    }

    companion object {
        private const val TAG = "AlarmReceiver"

        fun scheduleAlarm(
            context: Context,
            notificationId: Int,
            taskTitle: String,
            triggerTimeMillis: Long,
            isPermanent: Boolean
        ) {
            Log.d(TAG, "📅 ========== SCHEDULING ALARM ==========")
            Log.d(TAG, "  Task       : $taskTitle")
            Log.d(TAG, "  ID         : $notificationId")
            Log.d(TAG, "  Trigger at : $triggerTimeMillis")
            Log.d(TAG, "  Now        : ${System.currentTimeMillis()}")
            Log.d(TAG, "  Delta (s)  : ${(triggerTimeMillis - System.currentTimeMillis()) / 1000}")

            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val receiverIntent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra("taskTitle", taskTitle)
                putExtra("notificationId", notificationId)
            }
            val pi = PendingIntent.getBroadcast(
                context, notificationId, receiverIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                val showPI = PendingIntent.getActivity(
                    context, notificationId,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                am.setAlarmClock(
                    AlarmManager.AlarmClockInfo(triggerTimeMillis, showPI), pi
                )
                Log.d(TAG, "✅ Alarm set with setAlarmClock (highest priority)")
            } catch (e: Exception) {
                Log.e(TAG, "❌ setAlarmClock failed, trying fallback: ${e.message}", e)
                try {
                    am.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP, triggerTimeMillis, pi
                    )
                    Log.d(TAG, "⚠️ Fallback: setExactAndAllowWhileIdle")
                } catch (e2: Exception) {
                    Log.e(TAG, "❌ All alarm methods failed: ${e2.message}", e2)
                }
            }
        }

        fun cancelAlarm(context: Context, notificationId: Int) {
            Log.d(TAG, "🗑️ Canceling alarm ID: $notificationId")
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pi = PendingIntent.getBroadcast(
                context, notificationId,
                Intent(context, AlarmReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.cancel(pi)
            pi.cancel()
            AlarmService.stopAlarm(context)
            Log.d(TAG, "✅ Alarm canceled")
        }
    }
}
