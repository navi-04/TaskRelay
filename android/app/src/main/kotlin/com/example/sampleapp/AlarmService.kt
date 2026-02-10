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
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.app.NotificationCompat

/**
 * Foreground service that handles a triggered alarm.
 *
 * Shows alarm UI as a SYSTEM OVERLAY WINDOW — this bypasses Activity
 * launching which OnePlus/ColorOS silently blocks from background.
 * The overlay window is added directly via WindowManager and shows
 * over everything including the lock screen.
 */
class AlarmService : Service() {

    companion object {
        private const val TAG = "AlarmService"

        const val ACTION_START_ALARM = "com.example.sampleapp.ACTION_START_ALARM"
        const val ACTION_STOP_ALARM  = "com.example.sampleapp.ACTION_STOP_ALARM"

        private const val ALARM_NOTIFICATION_ID = 888
        private const val ALARM_CHANNEL_ID = "alarm_trigger_v2"

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
    private var currentTaskTitle: String = ""
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
        currentNotificationId = intent.getIntExtra("notificationId", 0)

        Log.d(TAG, "🔔 Starting alarm → $currentTaskTitle")

        // ── 1. FIRST: Go foreground with full-screen intent notification ──
        // This MUST happen before acquiring wake lock! If the device is
        // locked/idle, Android will trigger the full-screen intent and
        // launch AlarmActivity over the lock screen. If we wake the
        // screen first, Android treats the device as "in use" and just
        // shows a heads-up notification instead.
        
        // Acquire PARTIAL_WAKE_LOCK immediately to ensure CPU runs
        // while we wait for the delay.
        acquirePartialWakeLock()
        
        try {
        try {
            val notification = buildNotification(currentTaskTitle, currentNotificationId)
            startForeground(ALARM_NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ Foreground started — full-screen intent may trigger on lock screen")
        } catch (e: Exception) {
            Log.e(TAG, "❌ startForeground failed: ${e.message}", e)
        }

        // ── 2. Play sound immediately ────────────────────────────────
        startSound()

        // ── 3. Vibrate immediately ───────────────────────────────────
        startVibration()

        // ── 4. After a short delay, wake screen + show overlay ───────
        // The 250ms delay gives the full-screen intent time to fire.
        Handler(Looper.getMainLooper()).postDelayed({
            // Now we force the screen on (Full Wake Lock)
            acquireFullWakeLock()

            // Try to dismiss non-secure keyguard
            tryDismissKeyguard()

            // Show overlay (primary UI when screen is unlocked,
            // fallback when full-screen intent didn't fire)
            showOverlay(currentTaskTitle)
            
            // Release the partial lock now that we have the full one
            releasePartialWakeLock()
        }, 250)
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    // ─── Wake lock ───────────────────────────────────────────────────

    // ─── Wake lock ───────────────────────────────────────────────────

    private var partialWakeLock: PowerManager.WakeLock? = null

    private fun acquirePartialWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            partialWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SampleApp:AlarmPartial")
            partialWakeLock?.acquire(60_000L) // 1 min timeout
            Log.d(TAG, "✅ Partial wake lock acquired")
        } catch (e: Exception) { Log.e(TAG, "Partial WL failed: $e") }
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
            Log.d(TAG, "✅ Full Screen wake lock acquired — screen ON")
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

    // ─── Overlay Window (the actual alarm UI) ────────────────────────

    private fun showOverlay(taskTitle: String) {
        if (overlayView != null) {
            Log.d(TAG, "⚠️ Overlay already showing")
            return
        }

        // Check overlay permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            Log.e(TAG, "❌ No SYSTEM_ALERT_WINDOW permission — cannot show overlay")
            // Fall back to trying Activity launch
            tryLaunchActivity(taskTitle)
            return
        }

        try {
            val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager

            // Window params — shows over EVERYTHING including lock screen
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
                PixelFormat.TRANSLUCENT  // TRANSLUCENT composites over keyguard correctly
            )
            params.gravity = Gravity.CENTER

            // Allow overlay to extend into display cutout (notch) area
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                params.layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }

            // Build the alarm UI programmatically
            overlayView = buildAlarmUI(taskTitle)

            wm.addView(overlayView, params)
            Log.d(TAG, "✅ Overlay window added — alarm UI visible!")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Overlay failed: ${e.message}", e)
            // Fall back to Activity
            tryLaunchActivity(taskTitle)
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

    private fun tryLaunchActivity(taskTitle: String) {
        try {
            val activityIntent = Intent(this, AlarmActivity::class.java).apply {
                putExtra("taskTitle", taskTitle)
                putExtra("notificationId", currentNotificationId)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_NO_USER_ACTION
                )
            }
            startActivity(activityIntent)
            Log.d(TAG, "✅ Activity launched as fallback")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Activity fallback also failed: ${e.message}", e)
        }
    }

    /**
     * Build the alarm UI programmatically — orange fullscreen with
     * time, task title, snooze and dismiss buttons.
     */
    private fun buildAlarmUI(taskTitle: String): View {
        val density = resources.displayMetrics.density
        fun dp(v: Int) = (v * density).toInt()

        // Root layout — orange background
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(0xFFFF6B35.toInt()) // orange
            setPadding(dp(32), dp(60), dp(32), dp(48))
        }

        // Alarm icon
        val icon = TextView(this).apply {
            text = "⏰"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 80f)
            gravity = Gravity.CENTER
        }
        root.addView(icon)

        // Current time
        val now = java.util.Calendar.getInstance()
        val timeStr = String.format(
            "%02d:%02d",
            now.get(java.util.Calendar.HOUR_OF_DAY),
            now.get(java.util.Calendar.MINUTE)
        )
        val timeView = TextView(this).apply {
            text = timeStr
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 72f)
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        val timeParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(24) }
        root.addView(timeView, timeParams)

        // Task title
        val titleView = TextView(this).apply {
            text = taskTitle
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 28f)
            setTextColor(Color.WHITE)
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
        }
        val titleParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(32) }
        root.addView(titleView, titleParams)

        // "Task Alarm" label
        val label = TextView(this).apply {
            text = "Task Alarm"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            setTextColor(Color.argb(230, 255, 255, 255))
            gravity = Gravity.CENTER
        }
        val labelParams = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = dp(16) }
        root.addView(label, labelParams)

        // Spacer
        val spacer = View(this)
        root.addView(spacer, LinearLayout.LayoutParams(0, 0, 1f))

        // Button container
        val btnContainer = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }

        // Snooze button
        val snoozeBtn = Button(this).apply {
            text = "Snooze\n5 min"
            setTextColor(0xFFFF6B35.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            background = makeRoundedBg(Color.WHITE, dp(32).toFloat())
            setPadding(dp(24), dp(12), dp(24), dp(12))
            setOnClickListener {
                Log.d(TAG, "💤 Snooze pressed")
                val snoozeMs = System.currentTimeMillis() + 5 * 60 * 1000
                AlarmReceiver.scheduleAlarm(
                    this@AlarmService, currentNotificationId,
                    currentTaskTitle, snoozeMs, false
                )
                handleStopAlarm()
            }
        }
        val snoozeLp = LinearLayout.LayoutParams(0, dp(64), 1f).apply {
            marginEnd = dp(12)
        }
        btnContainer.addView(snoozeBtn, snoozeLp)

        // Dismiss button
        val dismissBtn = Button(this).apply {
            text = "Dismiss"
            setTextColor(0xFFFF6B35.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            typeface = Typeface.DEFAULT_BOLD
            background = makeRoundedBg(Color.WHITE, dp(32).toFloat())
            setPadding(dp(24), dp(12), dp(24), dp(12))
            setOnClickListener {
                Log.d(TAG, "🛑 Dismiss pressed")
                handleStopAlarm()
            }
        }
        val dismissLp = LinearLayout.LayoutParams(0, dp(64), 1f).apply {
            marginStart = dp(12)
        }
        btnContainer.addView(dismissBtn, dismissLp)

        root.addView(btnContainer, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ))

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
            // Delete old channel if it exists (cached settings might block full-screen intent)
            val nm = getSystemService(NotificationManager::class.java)
            try { nm.deleteNotificationChannel("alarm_trigger_channel") } catch (_: Exception) {}

            val channel = NotificationChannel(
                ALARM_CHANNEL_ID, "Alarm Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Full-screen alarm notifications that show over lock screen"
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                enableVibration(true)
                enableLights(true)
                setSound(null, null) // Sound handled by MediaPlayer, not notification
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(taskTitle: String, notificationId: Int): Notification {
        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("taskTitle", taskTitle)
            putExtra("notificationId", notificationId)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or 
                     Intent.FLAG_ACTIVITY_SINGLE_TOP or 
                     Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val fullScreenPI = PendingIntent.getActivity(
            this, notificationId, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val dismissPI = PendingIntent.getService(
            this, 0,
            Intent(this, AlarmService::class.java).apply { action = ACTION_STOP_ALARM },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, ALARM_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("⏰ Alarm")
            .setContentText(taskTitle)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPI, true)
            .setOngoing(true)
            .setAutoCancel(false)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Dismiss", dismissPI)
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
