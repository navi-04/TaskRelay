package com.example.sampleapp

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView

/**
 * Full-screen alarm Activity shown over the lock screen.
 *
 * Uses EVERY possible mechanism to ensure it displays:
 *   • Window flags (legacy + modern APIs)
 *   • KeyguardManager dismiss
 *   • PowerManager wake lock as last resort
 */
class AlarmActivity : Activity() {

    companion object {
        private const val TAG = "AlarmActivity"
        /** Static reference so AlarmService can finish this Activity
         *  when the alarm is dismissed from the overlay window. */
        @JvmStatic
        var currentInstance: AlarmActivity? = null
    }

    private lateinit var taskTitle: String
    private var notificationId: Int = 0
    private var screenWakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentInstance = this
        Log.d(TAG, "🔔 AlarmActivity onCreate")
        
        // ── 1. Set flags FIRST so window can show over lock screen ──
        try {
            // Apply LEGACY flags (still needed for some behaviors)
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_FULLSCREEN
            )
            
            // Apply MODERN API (Android 8.1+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }
            
            // Apply WAKE LOCK (Absolute backup)
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            screenWakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "SampleApp:AlarmActivityWake"
            )
            screenWakeLock?.acquire(30_000L) // 30 seconds max
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting flags: ${e.message}", e)
        }

        try {
            taskTitle = intent.getStringExtra("taskTitle") ?: "Task Reminder"
            notificationId = intent.getIntExtra("notificationId", 0)
            Log.d(TAG, "  Task: $taskTitle  ID: $notificationId")

            // ── 2. THEN set content ───────────────────────────────────
            setContentView(R.layout.activity_alarm)
            Log.d(TAG, "✅ setContentView done")

            // ── 3. Bind views ────────────────────────────────────────
            findViewById<TextView>(R.id.alarmTitle).text = taskTitle
            findViewById<TextView>(R.id.alarmTime).text = currentTimeString()

            findViewById<Button>(R.id.dismissButton).setOnClickListener {
                dismissAlarm()
            }
            findViewById<Button>(R.id.snoozeButton).setOnClickListener {
                snoozeAlarm()
            }

            Log.d(TAG, "✅ AlarmActivity fully ready and visible")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in onCreate UI setup: ${e.message}", e)
        }
    }

    // ─── Actions ─────────────────────────────────────────────────────

    private fun dismissAlarm() {
        Log.d(TAG, "🛑 Dismiss pressed")
        AlarmService.stopAlarm(this)
        releaseWakeLock()
        finish()
    }

    private fun snoozeAlarm() {
        Log.d(TAG, "💤 Snooze pressed – +5 min")
        AlarmService.stopAlarm(this)
        val snoozeMs = System.currentTimeMillis() + 5 * 60 * 1000
        AlarmReceiver.scheduleAlarm(this, notificationId, taskTitle, snoozeMs, false)
        releaseWakeLock()
        finish()
    }

    // ─── Lifecycle ───────────────────────────────────────────────────

    override fun onDestroy() {
        currentInstance = null
        releaseWakeLock()
        super.onDestroy()
        Log.d(TAG, "🛑 AlarmActivity onDestroy")
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Block — must dismiss or snooze
    }

    // ─── Helpers ─────────────────────────────────────────────────────

    private fun releaseWakeLock() {
        try {
            if (screenWakeLock?.isHeld == true) {
                screenWakeLock?.release()
                Log.d(TAG, "✅ Activity wake lock released")
            }
        } catch (_: Exception) {}
        screenWakeLock = null
    }

    private fun currentTimeString(): String {
        val now = java.util.Calendar.getInstance()
        return String.format(
            "%02d:%02d",
            now.get(java.util.Calendar.HOUR_OF_DAY),
            now.get(java.util.Calendar.MINUTE)
        )
    }
}
