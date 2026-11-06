package com.naveenraj.taskrelay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * A tap on a widget row. An open row is completed through the one Complete path ([AlarmActions.complete]: log, cache overlay,
 * widget refresh, one-time sync). A done row cannot be un-ticked from the widget: tapping it opens the app.
 */
class WidgetActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ROW_TAP) return
        val app = context.applicationContext
        val taskId = intent.getStringExtra(Extras.TASK_ID)
        val date = intent.getStringExtra(Extras.DATE)
        val done = intent.getBooleanExtra(EXTRA_DONE, false)
        val tapMs = System.currentTimeMillis()
        val pending = goAsync()
        Bg.io.execute {
            try {
                if (done || taskId == null || date == null) {
                    openApp(app)
                } else {
                    AlarmActions.complete(app, null, taskId, date, tapMs)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "row tap failed: ${t.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }

    private fun openApp(app: Context) {
        try {
            app.startActivity(Notifications.openAppIntent(app, "widget"))
        } catch (t: Throwable) {
            // Some launchers / OS versions do not allow an activity start from this broadcast: nothing else to do.
            Log.w(TAG, "could not open the app from the widget: ${t.javaClass.simpleName}")
        }
    }

    companion object {
        private const val TAG = "WidgetAction"
        const val ACTION_ROW_TAP = "com.naveenraj.taskrelay.action.WIDGET_ROW_TAP"
        const val EXTRA_DONE = "done"
    }
}
