package com.example.sampleapp

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
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
 * Launched via fullScreenIntent on the alarm notification.
 * Uses EVERY possible mechanism to ensure it displays on lock screen:
 *   - Window flags (legacy + modern APIs)
 *   - setShowWhenLocked / setTurnScreenOn (API 27+)
 *   - KeyguardManager.requestDismissKeyguard (for secure lock screens)
 *   - PowerManager wake lock (last resort screen wake)
 *
 * Works on Android 10–14 including Samsung, OnePlus, Xiaomi.
 */
class AlarmActivity : Activity() {

    private lateinit var taskTitle: String
    private var taskId: String = ""
    private var notificationId: Int = 0
    private var screenWakeLock: PowerManager.WakeLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentInstance = this
        Log.d(TAG, "🔔 AlarmActivity onCreate")

        // ── 1. Apply ALL lock screen flags BEFORE setContentView ─────
        applyLockScreenFlags()

        // ── 2. Extract intent data ───────────────────────────────────
        taskTitle = intent.getStringExtra("taskTitle") ?: "Task Reminder"
        taskId = intent.getStringExtra("taskId") ?: ""
        notificationId = intent.getIntExtra("notificationId", 0)
        Log.d(TAG, "  Task: $taskTitle  ID: $notificationId  TaskID: $taskId")

        // ── 3. Set content + bind views ──────────────────────────────
        try {
            setContentView(R.layout.activity_alarm)

            findViewById<TextView>(R.id.alarmTitle).text = taskTitle
            findViewById<TextView>(R.id.alarmTime).text = currentTimeString()

            findViewById<Button>(R.id.dismissButton).setOnClickListener {
                dismissAlarm()
            }
            findViewById<Button>(R.id.completeButton).setOnClickListener {
                markAsComplete()
            }

            Log.d(TAG, "✅ AlarmActivity fully ready")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error in onCreate UI setup: ${e.message}", e)
        }

        // ── 4. Request keyguard dismiss (for secure lock screens) ────
        requestKeyguardDismiss()
    }

    /**
     * Apply every possible mechanism to show over lock screen and wake display.
     */
    private fun applyLockScreenFlags() {
        try {
            // ── LEGACY window flags (needed for Android < 8.1 and some OEMs) ──
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_FULLSCREEN
            )

            // ── MODERN API (Android 8.1+ / API 27+) ──
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(true)
                setTurnScreenOn(true)
            }

            // ── WAKE LOCK — force screen on as absolute backup ──
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            screenWakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "SampleApp:AlarmActivityWake"
            )
            screenWakeLock?.acquire(60_000L) // 60 seconds max

            Log.d(TAG, "✅ Lock screen flags applied + wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error setting lock screen flags: ${e.message}", e)
        }
    }

    /**
     * Request keyguard dismissal. On secure lock screens (PIN/pattern/fingerprint),
     * this shows the unlock prompt overlaid on our Activity. Once the user
     * authenticates, the keyguard is dismissed and our Activity is fully interactive.
     *
     * On non-secure lock screens, this immediately dismisses the keyguard.
     */
    private fun requestKeyguardDismiss() {
        try {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                    override fun onDismissSucceeded() {
                        Log.d(TAG, "✅ Keyguard dismissed successfully")
                    }
                    override fun onDismissCancelled() {
                        Log.w(TAG, "⚠️ Keyguard dismiss cancelled by user")
                    }
                    override fun onDismissError() {
                        Log.e(TAG, "❌ Keyguard dismiss error")
                    }
                })
            } else {
                // Pre-O: use deprecated API
                @Suppress("DEPRECATION")
                val keyguardLock = km.newKeyguardLock("AlarmActivity")
                @Suppress("DEPRECATION")
                keyguardLock.disableKeyguard()
            }
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ requestDismissKeyguard failed: ${e.message}", e)
        }
    }

    // ─── Actions ─────────────────────────────────────────────────────

    private fun dismissAlarm() {
        Log.d(TAG, "🛑 Dismiss pressed")
        AlarmService.stopAlarm(this)
        releaseWakeLock()
        finish()
    }

    private fun markAsComplete() {
        Log.d(TAG, "✅ Mark as Complete pressed — taskId: $taskId")

        // Use the COMPLETE action so the service does NOT persist a dismissal
        try {
            val intent = Intent(this, AlarmService::class.java).apply {
                action = AlarmService.ACTION_COMPLETE_FROM_NOTIFICATION
            }
            startService(intent)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send complete action: ${e.message}", e)
            // Fallback: at least stop the alarm
            AlarmService.stopAlarm(this)
        }

        if (taskId.isNotEmpty()) {
            // ── PERSIST to SharedPreferences (survives app/process death) ──
            // This is the PRIMARY mechanism — Flutter reads it on next launch.
            persistPendingCompletion(this, taskId)

            // ── ALSO send broadcast (works if MainActivity is alive) ──
            val completeIntent = Intent("com.example.sampleapp.ACTION_COMPLETE_TASK").apply {
                setPackage(packageName)
                putExtra("taskId", taskId)
                putExtra("taskTitle", taskTitle)
            }
            sendBroadcast(completeIntent)
            Log.d(TAG, "📤 Complete broadcast sent for taskId: $taskId")
        }

        releaseWakeLock()
        finish()
    }

    companion object {
        private const val TAG = "AlarmActivity"
        private const val PREFS_NAME = "alarm_completions"
        private const val KEY_PENDING = "pending_task_ids"

        /** Static reference so AlarmService can finish this Activity
         *  when the alarm is dismissed from the overlay window. */
        @JvmStatic
        var currentInstance: AlarmActivity? = null

        /**
         * Persist a task completion to SharedPreferences so Flutter can pick it up
         * even if the app process was killed when the alarm fired.
         */
        @JvmStatic
        fun persistPendingCompletion(context: Context, taskId: String) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val pending = prefs.getStringSet(KEY_PENDING, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            pending.add(taskId)
            prefs.edit().putStringSet(KEY_PENDING, pending).apply()
            Log.d("AlarmActivity", "💾 Persisted pending completion: $taskId (total: ${pending.size})")
        }

        private const val DISMISSAL_PREFS_NAME = "alarm_dismissals"
        private const val KEY_DISMISSED = "dismissed_task_ids"

        /**
         * Persist a task dismissal to SharedPreferences so Flutter can clear
         * the alarm / mute recurring tasks on next launch.
         */
        @JvmStatic
        fun persistPendingDismissal(context: Context, taskId: String) {
            val prefs = context.getSharedPreferences(DISMISSAL_PREFS_NAME, Context.MODE_PRIVATE)
            val pending = prefs.getStringSet(KEY_DISMISSED, mutableSetOf())?.toMutableSet() ?: mutableSetOf()
            pending.add(taskId)
            prefs.edit().putStringSet(KEY_DISMISSED, pending).apply()
            Log.d("AlarmActivity", "💾 Persisted pending dismissal: $taskId (total: ${pending.size})")
        }
    }

    // ─── Lifecycle ───────────────────────────────────────────────────

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        // Handle re-launch if already showing (singleTask/singleTop)
        setIntent(intent)
        taskTitle = intent.getStringExtra("taskTitle") ?: taskTitle
        taskId = intent.getStringExtra("taskId") ?: taskId
        notificationId = intent.getIntExtra("notificationId", notificationId)
        try {
            findViewById<TextView>(R.id.alarmTitle)?.text = taskTitle
            findViewById<TextView>(R.id.alarmTime)?.text = currentTimeString()
        } catch (_: Exception) {}
        Log.d(TAG, "🔔 onNewIntent — updated for: $taskTitle")
    }

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
