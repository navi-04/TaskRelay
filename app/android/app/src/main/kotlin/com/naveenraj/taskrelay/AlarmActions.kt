package com.naveenraj.taskrelay

import android.content.Context
import android.util.Log
import java.time.ZoneId

/**
 * The only code that changes data in response to a user action on an alarm / notification / widget. Every surface (alarm screen,
 * notification buttons, widget row) calls into here; nothing else toggles a task or broadcasts to MainActivity.
 */
object AlarmActions {
    private const val TAG = "AlarmActions"
    const val SNOOZE_MS = 10 * 60_000L

    /**
     * ONE Complete path.
     *  1. append `taskId|date|complete|<tap ms>` to the ActionLog (fsync under a lock: the record survives anything after this line)
     *  2. stop the ring / remove the notification for that key
     *  3. mark done in TodayCache (+ pending overlay) and cancel the task's other armed alarms for that day
     *  4. refresh the widget
     *  5. re-check the app blocker (it reads the cache that step 3 just updated)
     *  6. enqueue a one-time sync
     *  7. ping Dart (`onActionsChanged`) if the engine is alive
     * [key] is the ringing entry's key, or null when the tap came from the widget.
     */
    fun complete(ctx: Context, key: String?, taskId: String, date: String, tapMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        val logged = try {
            Stores.actionLog(app).appendComplete(taskId, date, tapMs)
        } catch (t: Throwable) {
            Log.e(TAG, "could not append to the action log: ${t.javaClass.simpleName}")
            false
        }
        step("stop ring") {
            if (key != null) {
                AlarmService.stopIfRinging(key)
                Notifications.cancel(app, key)
            }
            AlarmService.stopIfRingingTask(taskId, date)
            Notifications.cancelTaskDay(app, taskId, date)
        }
        if (!logged) {
            Log.e(TAG, "complete not recorded (invalid ids or disk error); ring stopped only")
            return
        }
        step("today cache") { Stores.todayCache(app).markDone(taskId, date) }
        step("cancel task alarms") { AlarmScheduler.removeTaskDay(app, taskId, date) }
        step("widget") { TodayWidgetProvider.refreshAll(app) }
        step("app blocker") { BlockerAccessibilityService.reevaluate(app) } // the last task may just have been done: unblock at once
        step("enqueue sync") { SyncWorker.enqueueOnce(app) }
        DartBridge.actionsChanged()
    }

    /** Dismiss = stop only. No log, no server call, never alters data. */
    fun dismiss(ctx: Context, key: String?) {
        val app = ctx.applicationContext
        step("dismiss") {
            AlarmService.stopIfRinging(key)
            if (key != null) Notifications.cancel(app, key)
        }
    }

    /**
     * Snooze = stop the ring and add a native-owned `snooze` entry 10 minutes from now for the same task / date / title / kind.
     * Local only: nothing is logged or sent to the server.
     */
    fun snooze(ctx: Context, e: Entry, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        val zone = ZoneId.systemDefault()
        val trigger = nowMs + SNOOZE_MS
        val entry = Entry(
            key = Entry.keyFor(Kind.SNOOZE, e.taskId, e.date, Times.compactHhmm(trigger, zone)),
            kind = Kind.SNOOZE,
            taskId = e.taskId,
            date = e.date,
            localTime = Times.localHhmm(trigger, zone),
            title = e.title,
            triggerMs = trigger,
            origKind = e.ringKind,
        )
        step("stop ring") {
            AlarmService.stopIfRinging(e.key)
            Notifications.cancel(app, e.key)
        }
        step("arm snooze") { AlarmScheduler.addEntry(app, entry, nowMs) }
    }

    private inline fun step(what: String, block: () -> Unit) {
        try {
            block()
        } catch (t: Throwable) {
            Log.e(TAG, "$what failed: ${t.javaClass.simpleName}")
        }
    }
}
