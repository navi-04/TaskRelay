package com.naveenraj.taskrelay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Notification / alarm action buttons (Complete, Done, Snooze, Dismiss). Every PendingIntent carries all extras, so these work
 * after a service or process restart, and no service or activity is started just to relay a tap.
 */
class ActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val e = Entry.fromIntent(intent) ?: return
        val action = intent.action ?: return
        val app = context.applicationContext
        val pending = goAsync()
        Bg.io.execute {
            try {
                when (action) {
                    Notifications.ACTION_COMPLETE -> {
                        val id = e.taskId
                        if (id != null) AlarmActions.complete(app, e.key, id, e.date) else AlarmActions.dismiss(app, e.key)
                    }
                    Notifications.ACTION_SNOOZE -> AlarmActions.snooze(app, e)
                    Notifications.ACTION_DISMISS -> AlarmActions.dismiss(app, e.key)
                }
            } catch (t: Throwable) {
                Log.e("ActionReceiver", "action failed: ${t.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }
}
