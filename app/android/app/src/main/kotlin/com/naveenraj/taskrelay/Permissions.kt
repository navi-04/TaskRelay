package com.naveenraj.taskrelay

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.core.app.NotificationManagerCompat

/** Live system state of the three permissions the alarm UX depends on. */
object Permissions {
    /** POST_NOTIFICATIONS (API 33+) and the app-level notifications switch. */
    fun notificationsAllowed(ctx: Context): Boolean =
        NotificationManagerCompat.from(ctx.applicationContext).areNotificationsEnabled()

    /** SCHEDULE_EXACT_ALARM; always true below API 31. */
    fun exactAlarmAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = ctx.applicationContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    /** USE_FULL_SCREEN_INTENT is a runtime special-access toggle from API 34; always true below. */
    fun fullScreenIntentAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val nm = ctx.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.canUseFullScreenIntent()
    }
}
