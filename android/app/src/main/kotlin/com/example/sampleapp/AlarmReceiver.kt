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
 *   1. Posts notification with fullScreenIntent → AlarmActivity (lock screen)
 *   2. Plays alarm sound + vibration
 *   3. Shows overlay window as fallback (if FSI didn't fire)
 *
 * IMPORTANT: We do NOT launch AlarmActivity directly here.
 * Android 10+ blocks background activity launches from receivers.
 * The fullScreenIntent on the notification is the correct mechanism
 * — Android launches AlarmActivity when the screen is off/locked.
 */
class AlarmReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "🚨🚨🚨 ALARM TRIGGERED! 🚨🚨🚨")

        val taskTitle = intent.getStringExtra("taskTitle") ?: "Task Reminder"
        val taskId = intent.getStringExtra("taskId") ?: ""
        val notificationId = intent.getIntExtra("notificationId", 0)
        Log.d(TAG, "  Task: $taskTitle, ID: $notificationId, TaskID: $taskId")

        // ── Start AlarmService — it posts FSI notification + plays sound ─
        // Do NOT launch AlarmActivity directly. Do NOT wake screen.
        // The service will call startForeground() with a fullScreenIntent
        // notification, and Android will launch AlarmActivity if the screen
        // is off or the keyguard is showing.
        try {
            val svcIntent = Intent(context, AlarmService::class.java).apply {
                action = AlarmService.ACTION_START_ALARM
                putExtra("taskTitle", taskTitle)
                putExtra("taskId", taskId)
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
            isPermanent: Boolean,
            taskId: String = ""
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
                putExtra("taskId", taskId)
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
