package com.naveenraj.taskrelay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * The SINGLE owner of notification channels and of every notification the native layer posts.
 *
 *  - `alarm_critical_v5`: alarm sound, full-screen intent, bypasses Do Not Disturb where the user allowed it
 *  - `reminders`: task notifications, daily and end-of-day reminders (heads-up)
 *  - `missed`: "Missed: <title>" after an auto-stopped ring, a replaced ring, or a reboot that swallowed a trigger
 *
 * Notification id = key.hashCode() and 0x3FFFFFFF (a collision is harmless: the newer notification replaces the older one).
 */
object Notifications {
    private const val TAG = "Notifications"

    const val CH_ALARM = "alarm_critical_v5"
    const val CH_REMINDERS = "reminders"
    const val CH_MISSED = "missed"

    private val OLD_ALARM_CHANNELS = listOf("alarm_trigger_channel", "alarm_trigger_v2", "alarm_trigger_v3", "alarm_trigger_v4")

    const val ACTION_COMPLETE = "com.naveenraj.taskrelay.action.COMPLETE"
    const val ACTION_SNOOZE = "com.naveenraj.taskrelay.action.SNOOZE"
    const val ACTION_DISMISS = "com.naveenraj.taskrelay.action.DISMISS"

    private const val REQ_FSI = 11
    private const val REQ_OPEN = 12
    private const val REQ_ACTION = 13

    private const val FALLBACK_RING_TIMEOUT_MS = 3 * 60_000L

    fun idFor(key: String): Int = key.hashCode() and 0x3FFFFFFF

    private fun nm(ctx: Context) = ctx.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // ── channels ─────────────────────────────────────────────────────────────────────────────────────────────────

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = nm(ctx)
        for (old in OLD_ALARM_CHANNELS) {
            try {
                nm.deleteNotificationChannel(old)
            } catch (_: Exception) {
            }
        }

        val alarmSound: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val alarm = NotificationChannel(CH_ALARM, "Critical Alarm Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Full-screen alarms that show over the lock screen"
            setBypassDnd(true) // only takes effect when the user granted Do Not Disturb access
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 1000, 500, 1000, 500, 1000)
            enableLights(true)
            lightColor = 0xFFFFFFFF.toInt()
            setSound(
                alarmSound,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        val reminders = NotificationChannel(CH_REMINDERS, "Reminders", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "Task reminders, the daily plan and the end-of-day summary"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        val missed = NotificationChannel(CH_MISSED, "Missed alarms", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "Alarms and reminders that rang while you were away or that you did not answer"
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        nm.createNotificationChannels(listOf(alarm, reminders, missed))
    }

    // ── intents ──────────────────────────────────────────────────────────────────────────────────────────────────

    private val IMMUTABLE_UPDATE = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT

    /**
     * Opens the Flutter app. A distinct ACTION per use keeps the PendingIntents (and their extras) apart. It deliberately carries NO
     * data URI: with Flutter's default deep-link handling the embedding forwards `Intent.getData()` to Dart as route information,
     * which would push a bogus route into the app's router.
     */
    fun openAppIntent(ctx: Context, tag: String): Intent =
        Intent(ctx, MainActivity::class.java)
            .setAction("com.naveenraj.taskrelay.action.OPEN_${tag.uppercase()}")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    private fun openAppPI(ctx: Context): PendingIntent =
        PendingIntent.getActivity(ctx, REQ_OPEN, openAppIntent(ctx, "notification"), IMMUTABLE_UPDATE)

    private fun alarmActivityIntent(ctx: Context, e: Entry): Intent =
        e.putExtras(
            Intent(ctx, AlarmActivity::class.java)
                .setData(Uri.parse("taskrelay://ring/${e.key}"))
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NO_USER_ACTION or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP,
                ),
        )

    /** A notification / lock-screen action. Carries every extra so it works after a service or process restart. */
    private fun actionPI(ctx: Context, action: String, e: Entry): PendingIntent =
        PendingIntent.getBroadcast(
            ctx,
            REQ_ACTION,
            e.putExtras(
                Intent(ctx, ActionReceiver::class.java)
                    .setAction(action)
                    .setData(Uri.parse("taskrelay://action/${action.substringAfterLast('.').lowercase()}/${e.key}")),
            ),
            IMMUTABLE_UPDATE,
        )

    // ── alarm (ringing) ──────────────────────────────────────────────────────────────────────────────────────────

    /**
     * The alarm notification: full-screen intent to AlarmActivity, actions Complete / Snooze 10 min / Dismiss.
     * @param ongoing true for the foreground-service notification (cannot be swiped away while ringing)
     */
    fun buildRing(ctx: Context, e: Entry, ongoing: Boolean): Notification {
        val fsi = PendingIntent.getActivity(ctx, REQ_FSI, alarmActivityIntent(ctx, e), IMMUTABLE_UPDATE)
        val b = NotificationCompat.Builder(ctx, CH_ALARM)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle("Alarm")
            .setContentText(e.title)
            .setStyle(NotificationCompat.BigTextStyle().bigText(e.title))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fsi, true)
            .setContentIntent(fsi)
            .setOngoing(ongoing)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setDefaults(0)
            .addAction(0, "Complete", actionPI(ctx, ACTION_COMPLETE, e))
            .addAction(0, "Snooze 10 min", actionPI(ctx, ACTION_SNOOZE, e))
            .addAction(0, "Dismiss", actionPI(ctx, ACTION_DISMISS, e))
        if (!ongoing) b.setTimeoutAfter(FALLBACK_RING_TIMEOUT_MS)
        return b.build()
    }

    /**
     * Used when the ring service cannot start (foreground-service start not allowed): a full-screen-intent heads-up on the alarm
     * channel, whose own alarm sound (repeated until answered) is the ring.
     */
    fun postRingFallback(ctx: Context, e: Entry) {
        ensureChannels(ctx)
        val n = buildRing(ctx, e, ongoing = false)
        n.flags = n.flags or Notification.FLAG_INSISTENT
        notifySafely(ctx, idFor(e.key), n)
    }

    // ── task notifications and reminders ────────────────────────────────────────────────────────────────────────

    /** `notification` kind: a plain heads-up with Done and Snooze (no service, no activity trampoline). */
    fun postTask(ctx: Context, e: Entry) {
        ensureChannels(ctx)
        val text = if (e.kind == Kind.SNOOZE) "Snoozed reminder" else if (e.localTime.isNotEmpty()) "Reminder · ${e.localTime}" else "Reminder"
        val b = NotificationCompat.Builder(ctx, CH_REMINDERS)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(e.title)
            .setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(openAppPI(ctx))
        if (e.taskId != null) {
            b.addAction(0, "Done", actionPI(ctx, ACTION_COMPLETE, e))
            b.addAction(0, "Snooze 10 min", actionPI(ctx, ACTION_SNOOZE, e))
        }
        notifySafely(ctx, idFor(e.key), b.build())
    }

    /** Daily / end-of-day reminder; the body is composed at fire time (see ReminderText). */
    fun postReminder(ctx: Context, key: String, title: String, body: String) {
        ensureChannels(ctx)
        val n = NotificationCompat.Builder(ctx, CH_REMINDERS)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(openAppPI(ctx))
            .build()
        notifySafely(ctx, idFor(key), n)
    }

    /** "Missed: <title>": plain, no actions, opens the app. */
    fun postMissed(ctx: Context, key: String, title: String) {
        ensureChannels(ctx)
        val n = NotificationCompat.Builder(ctx, CH_MISSED)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle("Missed: $title")
            .setContentText("Tap to open TaskRelay")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setAutoCancel(true)
            .setContentIntent(openAppPI(ctx))
            .build()
        notifySafely(ctx, idFor("missed/$key"), n)
    }

    fun cancel(ctx: Context, key: String) {
        try {
            nm(ctx).cancel(idFor(key))
        } catch (_: Exception) {
        }
    }

    /** Cancels the notifications a task could currently be showing (its alarm / notification keys for that date). */
    fun cancelTaskDay(ctx: Context, taskId: String, date: String) {
        cancel(ctx, Entry.keyFor(Kind.ALARM, taskId, date))
        cancel(ctx, Entry.keyFor(Kind.NOTIFICATION, taskId, date))
    }

    fun cancelAll(ctx: Context) {
        try {
            nm(ctx).cancelAll()
        } catch (_: Exception) {
        }
    }

    private fun notifySafely(ctx: Context, id: Int, n: Notification) {
        try {
            nm(ctx).notify(id, n)
        } catch (t: Throwable) {
            // e.g. SecurityException when POST_NOTIFICATIONS was revoked mid-flight: nothing else to do
            Log.w(TAG, "notify failed: ${t.javaClass.simpleName}")
        }
    }
}
