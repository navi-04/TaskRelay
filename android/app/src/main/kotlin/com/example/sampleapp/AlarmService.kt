package com.example.sampleapp

import android.app.KeyguardManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * Foreground service that handles a triggered alarm.
 *
 * CRITICAL ORDER OF OPERATIONS for reliable lock-screen display:
 * 1. Post notification with fullScreenIntent via startForeground() FIRST
 *    → Android triggers FSI immediately if screen is off/locked
 * 2. Start alarm sound + vibration
 * 3. After a delay (3s), check if AlarmActivity appeared
 *    → If not, show overlay window as fallback
 *
 * NEVER wake the screen or launch activities BEFORE posting the FSI
 * notification. Doing so makes Android treat the device as "in use"
 * and it will show a heads-up notification instead of the full-screen
 * intent.
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"

        const val ACTION_START_ALARM = "com.example.sampleapp.ACTION_START_ALARM"
        const val ACTION_STOP_ALARM  = "com.example.sampleapp.ACTION_STOP_ALARM"
        const val ACTION_COMPLETE_FROM_NOTIFICATION = "com.example.sampleapp.ACTION_COMPLETE_FROM_NOTIFICATION"

        private const val ALARM_NOTIFICATION_ID = 888

        // ── FRESH channel ID — avoids any cached importance from old installs ──
        private const val ALARM_CHANNEL_ID = "alarm_critical_v5"

        // Old channel IDs to delete
        private val OLD_CHANNEL_IDS = listOf(
            "alarm_trigger_channel",
            "alarm_trigger_v2",
            "alarm_trigger_v3",
            "alarm_trigger_v4"
        )

        fun stopAlarm(context: Context) {
            try {
                val intent = Intent(context, AlarmService::class.java).apply {
                    action = ACTION_STOP_ALARM
                }
                context.startService(intent)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to send stop: ${e.message}", e)
            }
        }
    }

    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var overlayView: View? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var partialWakeLock: PowerManager.WakeLock? = null
    private var currentTaskTitle: String = ""
    private var currentTaskId: String = ""
    private var currentNotificationId: Int = 0

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "📱 AlarmService onCreate")
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "🚀 onStartCommand action=${intent?.action}")

        when (intent?.action) {
            ACTION_START_ALARM -> handleStartAlarm(intent)
            ACTION_STOP_ALARM  -> handleStopAlarm()
            ACTION_COMPLETE_FROM_NOTIFICATION -> handleCompleteFromNotification()
            else -> {
                Log.w(TAG, "⚠️ Unknown action")
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        Log.d(TAG, "🛑 AlarmService onDestroy")
        removeOverlay()
        releaseResources()
        releaseWakeLock()
        super.onDestroy()
    }

    // ─── Start alarm ─────────────────────────────────────────────────

    private fun handleStartAlarm(intent: Intent) {
        currentTaskTitle = intent.getStringExtra("taskTitle") ?: "Task Reminder"
        currentTaskId = intent.getStringExtra("taskId") ?: ""
        currentNotificationId = intent.getIntExtra("notificationId", 0)

        Log.d(TAG, "🔔 Starting alarm → $currentTaskTitle (ID: $currentNotificationId, TaskID: $currentTaskId)")

        // ── STEP 1: Go foreground with FSI notification IMMEDIATELY ──
        // This is the ONLY reliable way to show UI on the lock screen.
        // Android triggers the fullScreenIntent when:
        //   • The notification channel has IMPORTANCE_HIGH
        //   • The screen is off OR the keyguard is showing
        //   • The app has USE_FULL_SCREEN_INTENT permission
        //
        // ⚠️ Do NOT wake the screen or launch activities before this!
        // That makes Android think the device is "in use" and it will
        // show a heads-up notification instead of launching AlarmActivity.
        try {
            val notification = buildNotification(currentTaskTitle, currentNotificationId)
            startForeground(ALARM_NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Foreground started with FSI — system will launch AlarmActivity if screen is off")
        } catch (e: Exception) {
            Log.e(TAG, "❌ startForeground failed: ${e.message}", e)
        }

        // ── STEP 2: Acquire partial wake lock to keep CPU running ────
        // PARTIAL only — does NOT turn screen on (that would break FSI)
        acquirePartialWakeLock()

        // ── STEP 3: Start sound + vibration immediately ──────────────
        startSound()
        startVibration()

        // ── STEP 4: Delayed fallback — only if FSI didn't launch Activity ──
        // Wait 3 seconds for the FSI to trigger and AlarmActivity to appear.
        // If it didn't (OEM blocked it, permission missing, etc.), use fallback.
        //
        // HOWEVER: if the screen is already on AND unlocked, Android will
        // intentionally show a heads-up notification instead of the FSI.
        // In that case we do NOT want the overlay — the notification alone
        // (with Dismiss / Mark as Complete actions) is the correct UX.
        Handler(Looper.getMainLooper()).postDelayed({
            if (AlarmActivity.currentInstance != null) {
                // AlarmActivity is already showing — FSI worked!
                Log.d(TAG, "✅ AlarmActivity is visible — FSI triggered successfully")
                releasePartialWakeLock()
                return@postDelayed
            }

            // Check if screen is on AND not locked — user is actively using phone
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            val screenOn = pm.isInteractive
            val unlocked = !km.isKeyguardLocked

            if (screenOn && unlocked) {
                // Screen on + unlocked → heads-up notification is already showing
                // with Dismiss & Complete actions. No overlay/activity needed.
                Log.d(TAG, "✅ Screen on & unlocked — heads-up notification is sufficient, skipping overlay")
                releasePartialWakeLock()
                return@postDelayed
            }

            Log.w(TAG, "⚠️ AlarmActivity NOT visible after 3s (screen locked or off) — using fallback")

            // Now it's safe to wake the screen (FSI had its chance)
            acquireFullWakeLock()

            // Try to dismiss non-secure keyguard
            tryDismissKeyguard()

            // Show overlay window as fallback (needs SYSTEM_ALERT_WINDOW)
            showOverlay(currentTaskTitle)

            releasePartialWakeLock()
        }, 3000)
    }

    /**
     * Try to dismiss the keyguard. This only works for non-secure
     * lock screens (swipe-to-unlock). Secure lock screens (PIN/pattern/
     * fingerprint) cannot be dismissed from a service — the full-screen
     * intent on the notification handles those cases by launching
     * AlarmActivity with showWhenLocked="true".
     */
    private fun tryDismissKeyguard() {
        try {
            val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (km.isKeyguardLocked) {
                Log.d(TAG, "🔒 Keyguard is locked — attempting dismiss")
                @Suppress("DEPRECATION")
                val keyguardLock = km.newKeyguardLock("AlarmService")
                keyguardLock.disableKeyguard()
                Log.d(TAG, "✅ disableKeyguard called (works for non-secure only)")
            } else {
                Log.d(TAG, "🔓 Keyguard not locked — overlay will be visible")
            }
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Keyguard dismiss failed: ${e.message}")
        }
    }

    /**
     * "Mark as Complete" tapped from the heads-up notification action button.
     * Persists the completion, sends broadcast to Flutter, then stops the alarm.
     */
    private fun handleCompleteFromNotification() {
        Log.d(TAG, "✅ Mark as Complete from notification — taskId: $currentTaskId")
        if (currentTaskId.isNotEmpty()) {
            // Persist to SharedPreferences (survives process death)
            AlarmActivity.persistPendingCompletion(this, currentTaskId)
            // Also send broadcast (works if MainActivity is alive)
            val completeIntent = Intent("com.example.sampleapp.ACTION_COMPLETE_TASK").apply {
                setPackage(packageName)
                putExtra("taskId", currentTaskId)
                putExtra("taskTitle", currentTaskTitle)
            }
            sendBroadcast(completeIntent)
            Log.d(TAG, "📤 Complete broadcast sent for taskId: $currentTaskId")
        }
        handleStopAlarm()
    }

    private fun handleStopAlarm() {
        Log.d(TAG, "🛑 Stopping alarm")
        removeOverlay()
        releaseResources()
        releaseWakeLock()

        // Also close AlarmActivity if it was launched via full-screen intent
        try {
            AlarmActivity.currentInstance?.finish()
            Log.d(TAG, "✅ AlarmActivity finished")
        } catch (e: Exception) {
            Log.e(TAG, "⚠️ Could not finish AlarmActivity: ${e.message}")
        }

        // Cancel the ongoing notification
        try {
            val nm = getSystemService(NotificationManager::class.java)
            nm.cancel(ALARM_NOTIFICATION_ID)
        } catch (_: Exception) {}

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    // ─── Wake lock ───────────────────────────────────────────────────

    private fun acquirePartialWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            partialWakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "SampleApp:AlarmPartial"
            )
            partialWakeLock?.acquire(60_000L) // 1 min timeout
            Log.d(TAG, "✅ Partial wake lock acquired (CPU only, screen stays off)")
        } catch (e: Exception) {
            Log.e(TAG, "Partial WL failed: $e")
        }
    }

    private fun releasePartialWakeLock() {
        try {
            if (partialWakeLock?.isHeld == true) partialWakeLock?.release()
        } catch (_: Exception) {}
        partialWakeLock = null
    }

    private fun acquireFullWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            @Suppress("DEPRECATION")
            wakeLock = pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP,
                "SampleApp:AlarmWake"
            )
            wakeLock?.acquire(5 * 60_000L) // 5 minutes max
            Log.d(TAG, "✅ Full wake lock acquired — screen ON")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Wake lock failed: ${e.message}", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "✅ Wake lock released")
            }
        } catch (_: Exception) {}
        wakeLock = null
        releasePartialWakeLock()
    }

    // ─── Overlay Window (fallback alarm UI) ──────────────────────────

    private fun showOverlay(taskTitle: String) {
        // Don't show overlay if AlarmActivity is already visible
        if (AlarmActivity.currentInstance != null) {
            Log.d(TAG, "✅ AlarmActivity already showing — skipping overlay")
            return
        }

        if (overlayView != null) {
            Log.d(TAG, "⚠️ Overlay already showing")
            return
        }

        // Check overlay permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.e(TAG, "❌ No SYSTEM_ALERT_WINDOW permission — cannot show overlay")
            return
        }

        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
            }

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                layoutType,
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                        WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                        WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.CENTER

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                params.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }

            overlayView = buildAlarmUI(taskTitle)
            wm.addView(overlayView, params)
            Log.d(TAG, "✅ Overlay window added — fallback alarm UI visible!")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Overlay failed: ${e.message}", e)
        }
    }

    private fun removeOverlay() {
        try {
            if (overlayView != null) {
                val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                wm.removeView(overlayView)
                overlayView = null
                Log.d(TAG, "✅ Overlay removed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing overlay: ${e.message}", e)
            overlayView = null
        }
    }

    /**
     * Build the alarm UI programmatically — modern transparent glassmorphic card
     * centered on a dark translucent scrim, with Mark as Complete and Dismiss.
     */
    private fun buildAlarmUI(taskTitle: String): View {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        // Root — dark translucent scrim over entire screen
        val root = FrameLayout(this).apply {
            setBackgroundColor(0xCC000000.toInt())
        }

        // Card container — centered frosted glass card
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = makeRoundedBg(0x55FFFFFF.toInt(), dp(28).toFloat()).apply {
                setStroke(dp(1), 0x33FFFFFF.toInt())
            }
            setPadding(dp(32), dp(32), dp(32), dp(32))
        }

        // Icon — bell inside a ring
        val iconBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(0x44FFFFFF.toInt())
            setStroke(dp(2), 0x88FFFFFF.toInt())
        }
        val icon = TextView(this).apply {
            text = "🔔"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 44f)
            gravity = Gravity.CENTER
            background = iconBg
        }
        card.addView(icon, LinearLayout.LayoutParams(dp(80), dp(80)).apply {
            gravity = Gravity.CENTER_HORIZONTAL
        })

        // "ALARM" label
        val alarmLabel = TextView(this).apply {
            text = "ALARM"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(0x80FFFFFF.toInt())
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            letterSpacing = 0.3f
        }
        card.addView(alarmLabel, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(20) })

        // Current time
        val now = java.util.Calendar.getInstance()
        val timeStr = String.format(
            "%02d:%02d",
            now.get(java.util.Calendar.HOUR_OF_DAY),
            now.get(java.util.Calendar.MINUTE)
        )
        val timeView = TextView(this).apply {
            text = timeStr
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 56f)
            setTextColor(Color.WHITE)
            typeface = Typeface.create("sans-serif-light", Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        card.addView(timeView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(4) })

        // Divider
        val divider = View(this).apply {
            setBackgroundColor(0x33FFFFFF.toInt())
        }
        card.addView(divider, LinearLayout.LayoutParams(dp(48), dp(2)).apply {
            topMargin = dp(16)
            gravity = Gravity.CENTER_HORIZONTAL
        })

        // Task title
        val titleView = TextView(this).apply {
            text = taskTitle
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 22f)
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            maxLines = 3
        }
        card.addView(titleView, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(16) })

        // "Mark as Complete" button — green
        val completeBtn = Button(this).apply {
            text = "✓  Mark as Complete"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            typeface = Typeface.DEFAULT_BOLD
            isAllCaps = false
            background = makeRoundedBg(0xFF4CAF50.toInt(), dp(16).toFloat())
            setPadding(dp(16), dp(14), dp(16), dp(14))
            stateListAnimator = null
            setOnClickListener {
                Log.d(TAG, "✅ Complete pressed (overlay)")
                // Persist to SharedPreferences (survives process death)
                if (currentTaskId.isNotEmpty()) {
                    AlarmActivity.persistPendingCompletion(this@AlarmService, currentTaskId)
                }
                // Also send broadcast (works if MainActivity is alive)
                if (currentTaskId.isNotEmpty()) {
                    val completeIntent = Intent("com.example.sampleapp.ACTION_COMPLETE_TASK").apply {
                        setPackage(packageName)
                        putExtra("taskId", currentTaskId)
                        putExtra("taskTitle", currentTaskTitle)
                    }
                    sendBroadcast(completeIntent)
                    Log.d(TAG, "📤 Complete broadcast sent for taskId: $currentTaskId")
                }
                handleStopAlarm()
            }
        }
        card.addView(completeBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(56)
        ).apply { topMargin = dp(32) })

        // "Dismiss" button — transparent text
        val dismissBtn = Button(this).apply {
            text = "Dismiss"
            setTextColor(0x80FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            isAllCaps = false
            setBackgroundColor(Color.TRANSPARENT)
            stateListAnimator = null
            setOnClickListener {
                Log.d(TAG, "🛑 Dismiss pressed (overlay)")
                handleStopAlarm()
            }
        }
        card.addView(dismissBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, dp(48)
        ).apply { topMargin = dp(12) })

        // Add card to root, centered with margins
        val cardParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = Gravity.CENTER
            marginStart = dp(24)
            marginEnd = dp(24)
        }
        root.addView(card, cardParams)

        return root
    }

    private fun makeRoundedBg(color: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = radius
            setColor(color)
        }
    }

    // ─── Notification ────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)

            // Delete ALL old channels to avoid cached importance issues
            for (oldId in OLD_CHANNEL_IDS) {
                try { nm.deleteNotificationChannel(oldId) } catch (_: Exception) {}
            }

            // Build alarm sound URI for the channel
            val alarmSoundUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val alarmAudioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            val channel = NotificationChannel(
                ALARM_CHANNEL_ID,
                "Critical Alarm Alerts",
                NotificationManager.IMPORTANCE_HIGH  // Maximum allowed for channels
            ).apply {
                description = "Full-screen alarm notifications that show over lock screen"
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
                enableLights(true)
                lightColor = 0xFFFF6B35.toInt()
                // Set alarm sound on the channel — critical for some OEMs to treat
                // this as a true alarm notification and honor the fullScreenIntent
                setSound(alarmSoundUri, alarmAudioAttributes)
            }
            nm.createNotificationChannel(channel)
            Log.d(TAG, "✅ Notification channel '$ALARM_CHANNEL_ID' created (IMPORTANCE_HIGH, alarm sound, bypass DND)")
        }
    }

    private fun buildNotification(taskTitle: String, notificationId: Int): Notification {
        // ── Full-screen intent → AlarmActivity ──
        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("taskTitle", taskTitle)
            putExtra("taskId", currentTaskId)
            putExtra("notificationId", notificationId)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            )
        }
        val fullScreenPI = PendingIntent.getActivity(
            this, notificationId, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Dismiss action ──
        val dismissPI = PendingIntent.getService(
            this, notificationId + 900000,
            Intent(this, AlarmService::class.java).apply { action = ACTION_STOP_ALARM },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // ── Mark as Complete action ──
        val completePI = PendingIntent.getService(
            this, notificationId + 800000,
            Intent(this, AlarmService::class.java).apply { action = ACTION_COMPLETE_FROM_NOTIFICATION },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("⏰ Alarm")
            .setContentText(taskTitle)
            .setStyle(NotificationCompat.BigTextStyle().bigText(taskTitle))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPI, true)
            .setContentIntent(fullScreenPI)
            .setOngoing(true)
            .setAutoCancel(false)
            .setDefaults(0) // We handle sound/vibration ourselves via MediaPlayer
            .setSilent(false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissPI)
            .addAction(android.R.drawable.ic_menu_send, "✓ Complete", completePI)
            .build()
    }

    // ─── Sound ───────────────────────────────────────────────────────

    private fun startSound() {
        try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            mediaPlayer = MediaPlayer().apply {
                setDataSource(applicationContext, uri)
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build())
                setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
                isLooping = true
                setVolume(1f, 1f)
                prepare()
                start()
            }
            Log.d(TAG, "✅ Sound playing")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Sound failed: ${e.message}", e)
        }
    }

    private fun startVibration() {
        try {
            @Suppress("DEPRECATION")
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator?.vibrate(
                    VibrationEffect.createWaveform(pattern, 0),
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build()
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(pattern, 0)
            }
            Log.d(TAG, "✅ Vibration started")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Vibration failed: ${e.message}", e)
        }
    }

    private fun releaseResources() {
        try {
            mediaPlayer?.apply { if (isPlaying) stop(); release() }
            mediaPlayer = null
        } catch (e: Exception) { mediaPlayer = null }
        try { vibrator?.cancel() } catch (_: Exception) {}
    }
}
