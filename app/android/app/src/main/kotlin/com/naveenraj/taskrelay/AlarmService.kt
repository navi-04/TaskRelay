package com.naveenraj.taskrelay

import android.app.Notification
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
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
import android.os.VibratorManager
import android.util.Log

/**
 * Foreground service (type `mediaPlayback` only) that rings ONE alarm: looping sound + vibration, with the full-screen-intent
 * notification that opens AlarmActivity over the lock screen.
 *
 *  - a second ACTION_START_ALARM while ringing updates the notification and never creates a second MediaPlayer;
 *  - the ring stops by itself after 3 minutes and posts "Missed: <title>" (the timer is cancelled in onDestroy);
 *  - there is no overlay window and no SYSTEM_ALERT_WINDOW: the heads-up / full-screen notification is the UI. If the screen is
 *    on and unlocked the heads-up is enough; on the lock screen the full-screen intent launches AlarmActivity.
 *  - every notification action carries its own extras (key, taskId, date, title, kind), so it works after a service restart.
 */
class AlarmService : Service() {

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var current: Entry? = null
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { onRingTimeout() }

    override fun onCreate() {
        super.onCreate()
        instance = this
        Notifications.ensureChannels(this)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START_ALARM -> startRinging(Entry.fromIntent(intent))
            ACTION_STOP_ALARM -> stopRinging()
            else -> if (current == null) stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null) // cancels the 3-minute timeout
        releasePlayer()
        cancelVibration()
        releaseWakeLock()
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ── ring ─────────────────────────────────────────────────────────────────────────────────────────────────────

    private fun startRinging(e: Entry?) {
        if (e == null) {
            // Started with startForegroundService: must still go foreground within 5 s, then leave.
            tryForeground(Notifications.buildRing(this, Entry("none/-/-", Kind.ALARM, null, "", "", "Alarm", 0L), ongoing = true))
            stopRinging()
            return
        }

        // Foreground FIRST (the 5-second rule). If this fails, hand over to the full-screen heads-up notification, whose channel
        // plays the alarm sound, and do not ring from here.
        if (!tryForeground(Notifications.buildRing(this, e, ongoing = true))) {
            Notifications.postRingFallback(this, e)
            stopRinging(removeNotification = false)
            return
        }

        val previous = current
        if (previous != null && previous.key != e.key) {
            // Another alarm was ringing and is now replaced: it must not vanish silently.
            Notifications.postMissed(this, previous.key, previous.title)
        }
        current = e

        acquireWakeLock()
        if (player == null) startSound() // NEVER a second MediaPlayer: a repeat start only refreshes the notification
        if (vibrator == null) startVibration()

        handler.removeCallbacks(timeout)
        handler.postDelayed(timeout, RING_TIMEOUT_MS)

        if (AlarmActivity.instance != null) AlarmActivity.instance?.updateFrom(e)
        else if (!Permissions.notificationsAllowed(this)) Notifications.openAlarmScreen(this, e) // no notification, so no other way to silence it
    }

    private fun tryForeground(n: Notification): Boolean = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(FOREGROUND_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(FOREGROUND_ID, n)
        }
        true
    } catch (t: Throwable) {
        Log.e(TAG, "startForeground failed: ${t.javaClass.simpleName}")
        false
    }

    /** Stops sound / vibration / UI and the service. Safe to call repeatedly. */
    fun stopRinging(removeNotification: Boolean = true) {
        handler.removeCallbacks(timeout)
        releasePlayer()
        cancelVibration()
        releaseWakeLock()
        current = null
        AlarmActivity.finishIfShowing()
        if (removeNotification) {
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (_: Exception) {
            }
        }
        stopSelf()
    }

    private fun onRingTimeout() {
        val e = current
        stopRinging()
        if (e != null) Notifications.postMissed(applicationContext, e.key, e.title)
    }

    // ── sound / vibration / wake lock ────────────────────────────────────────────────────────────────────────────

    private val alarmAudio: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()

    /** Looping alarm sound: the user's default alarm tone, then ringtone / notification tone, then the bundled res/raw/alarm_sound. */
    private fun startSound() {
        releasePlayer() // defensive: never two players
        val uris = listOfNotNull(
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
        )
        for (uri in uris) {
            player = tryPlayer { setDataSource(applicationContext, uri) }
            if (player != null) return
        }
        player = tryPlayer {
            applicationContext.resources.openRawResourceFd(R.raw.alarm_sound).use {
                setDataSource(it.fileDescriptor, it.startOffset, it.length)
            }
        }
        if (player == null) Log.e(TAG, "no alarm sound could be played")
    }

    private fun tryPlayer(source: MediaPlayer.() -> Unit): MediaPlayer? {
        val mp = MediaPlayer()
        return try {
            mp.setAudioAttributes(alarmAudio)
            mp.source()
            mp.isLooping = true
            mp.setVolume(1f, 1f)
            mp.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            mp.setOnErrorListener { _, _, _ ->
                releasePlayer()
                true
            }
            mp.prepare()
            mp.start()
            mp
        } catch (t: Exception) {
            try {
                mp.release()
            } catch (_: Exception) {
            }
            null
        }
    }

    private fun releasePlayer() {
        val p = player ?: return
        player = null
        try {
            if (p.isPlaying) p.stop()
        } catch (_: Exception) {
        }
        try {
            p.release()
        } catch (_: Exception) {
        }
    }

    private fun startVibration() {
        try {
            val v: Vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            vibrator = v
            val pattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                v.vibrate(VibrationEffect.createWaveform(pattern, 0), alarmAudio)
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "vibration failed: ${t.javaClass.simpleName}")
        }
    }

    private fun cancelVibration() {
        try {
            vibrator?.cancel()
        } catch (_: Exception) {
        }
        vibrator = null
    }

    /** A short PARTIAL wake lock covers the start-up; MediaPlayer's own wake mode covers playback. */
    private fun acquireWakeLock() {
        try {
            releaseWakeLock()
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "taskrelay:alarm").also { it.acquire(WAKE_LOCK_MS) }
        } catch (t: Throwable) {
            Log.w(TAG, "wake lock failed: ${t.javaClass.simpleName}")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (_: Exception) {
        }
        wakeLock = null
    }

    companion object {
        private const val TAG = "AlarmService"

        const val ACTION_START_ALARM = "com.naveenraj.taskrelay.ACTION_START_ALARM"
        const val ACTION_STOP_ALARM = "com.naveenraj.taskrelay.ACTION_STOP_ALARM"

        /** The single foreground notification id: there is one ring slot. */
        const val FOREGROUND_ID = 888
        const val RING_TIMEOUT_MS = 3 * 60_000L
        private const val WAKE_LOCK_MS = 30_000L

        @Volatile
        private var instance: AlarmService? = null

        /** Stops the ring when it belongs to [key] (or any ring when [key] is null). No-op when nothing is ringing. */
        fun stopIfRinging(key: String?) {
            Bg.main.post {
                val s = instance ?: return@post
                if (key == null || s.current?.key == key) s.stopRinging()
            }
        }

        /** Stops the ring when it is for this task occurrence (a Complete from the widget or another surface). */
        fun stopIfRingingTask(taskId: String, date: String) {
            Bg.main.post {
                val s = instance ?: return@post
                val c = s.current ?: return@post
                if (c.taskId == taskId && c.date == date) s.stopRinging()
            }
        }
    }
}
