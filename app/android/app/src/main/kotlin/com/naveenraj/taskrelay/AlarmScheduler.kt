package com.naveenraj.taskrelay

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import java.time.ZoneId

/**
 * Owns every AlarmManager registration. All mutating entry points run under ONE process-wide lock ([AlarmStore.LOCK]).
 *
 * PendingIntent identity = the data URI `taskrelay://alarm/<key>` on the receiver Intent with a CONSTANT request code, so a key
 * maps to exactly one registration (no String.hashCode of task ids). Arm with FLAG_IMMUTABLE|FLAG_UPDATE_CURRENT, look up / cancel
 * with FLAG_NO_CREATE|FLAG_IMMUTABLE.
 *
 * Only the nearest [AlarmDiff.MAX_ARMED] future entries are armed (Android caps an app near 500 alarms); [rearmFromStore] tops the
 * set up after boot, after every fire and after every apply. This class never touches AlarmService: replacing the plan can
 * never stop an alarm that is ringing.
 */
object AlarmScheduler {
    private const val TAG = "AlarmScheduler"
    private const val REQ_ALARM = 1
    private const val REQ_SHOW = 2

    /** Entries older than this are pruned from the store; younger past entries are what BootReceiver reports as missed. */
    const val MISSED_WINDOW_MS = 6 * 60 * 60_000L

    // ── public API ───────────────────────────────────────────────────────────────────────────────────────────────

    /** Replaces the stored plan with [planned]: diff by key, cancel what disappeared, arm what is new / changed. */
    fun replaceAll(ctx: Context, planned: List<Entry>, nowMs: Long = System.currentTimeMillis()) {
        apply(ctx.applicationContext, planned, nowMs, force = false)
    }

    /**
     * Re-arms from the persisted entries (nothing is re-planned). [force] ignores what the OS currently holds and arms the nearest
     * entries again (after boot / app update / exact-alarm permission change, when every registration was wiped).
     */
    fun rearmFromStore(ctx: Context, force: Boolean = false, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val entries = Stores.alarmStore(app).read().entries.filter { it.triggerMs > nowMs - MISSED_WINDOW_MS }
            apply(app, entries, nowMs, force)
        }
    }

    /** Cancels EVERY registration the store knows about and wipes the store (sign-out). */
    fun cancelAll(ctx: Context) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val store = Stores.alarmStore(app)
            val am = alarmManager(app)
            for (e in store.read().entries) cancelKey(app, am, e.key)
            store.clear()
        }
    }

    /** Adds (or replaces) one entry, e.g. a snooze, and arms it. */
    fun addEntry(ctx: Context, entry: Entry, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val current = Stores.alarmStore(app).read().entries.filter { it.key != entry.key }
            apply(app, current + entry, nowMs, force = false)
        }
    }

    /** Forgets an entry that has just fired (its registration is consumed) and tops the armed set up. */
    fun markFired(ctx: Context, key: String, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val current = Stores.alarmStore(app).read().entries.filter { it.key != key && it.triggerMs > nowMs - MISSED_WINDOW_MS }
            apply(app, current, nowMs, force = false)
        }
    }

    /** Cancels every armed alarm / notification / snooze of one task occurrence (it was just completed). */
    fun removeTaskDay(ctx: Context, taskId: String, date: String, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val all = Stores.alarmStore(app).read().entries
            val keep = all.filterNot { Kind.isTaskKind(it.kind) && it.taskId == taskId && it.date == date }
            if (keep.size != all.size) apply(app, keep, nowMs, force = false)
        }
    }

    /** Cancels and forgets specific keys (e.g. entries that were reported as missed). */
    fun removeKeys(ctx: Context, keys: Set<String>, nowMs: Long = System.currentTimeMillis()) {
        if (keys.isEmpty()) return
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val all = Stores.alarmStore(app).read().entries
            val keep = all.filter { it.key !in keys }
            if (keep.size != all.size) apply(app, keep, nowMs, force = false)
        }
    }

    /**
     * Task entries (alarm / notification / snooze) whose trigger passed within the last 6 hours without ringing: returned for a
     * "Missed" notification and forgotten, together with every other past entry.
     */
    fun takeMissed(ctx: Context, nowMs: Long = System.currentTimeMillis()): List<Entry> {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val all = Stores.alarmStore(app).read().entries
            val missed = all.filter { Kind.isTaskKind(it.kind) && it.triggerMs <= nowMs && it.triggerMs > nowMs - MISSED_WINDOW_MS }
            val keep = all.filter { it.triggerMs > nowMs }
            if (keep.size != all.size) apply(app, keep, nowMs, force = false)
            return missed
        }
    }

    /**
     * Wall-clock entries are re-resolved to instants in [zone] after a clock or timezone change (snoozes are absolute instants and
     * are left alone), then every registration is refreshed.
     */
    fun reResolve(ctx: Context, zone: ZoneId, nowMs: Long = System.currentTimeMillis()) {
        val app = ctx.applicationContext
        synchronized(AlarmStore.LOCK) {
            val moved = Stores.alarmStore(app).read().entries.map { e ->
                if (e.kind == Kind.SNOOZE) e else Times.resolve(e.date, e.localTime, zone)?.let { e.copy(triggerMs = it) } ?: e
            }
            apply(app, moved, nowMs, force = true)
        }
    }

    // ── core ─────────────────────────────────────────────────────────────────────────────────────────────────────

    private fun apply(app: Context, planned: List<Entry>, nowMs: Long, force: Boolean) {
        synchronized(AlarmStore.LOCK) {
            val store = Stores.alarmStore(app)
            val am = alarmManager(app)
            val sorted = planned.sortedWith(FeedPlanner.ORDER)
            val stored = store.read().entries

            val plan = AlarmDiff.compute(stored, sorted, nowMs, AlarmDiff.MAX_ARMED) { key -> !force && isArmed(app, key) }

            // Persist the desired set FIRST: if we die while arming, the next rearmFromStore finishes the job.
            store.update { it.copy(entries = sorted) }

            for (key in plan.toCancel) cancelKey(app, am, key)

            var exactOk = Permissions.exactAlarmAllowed(app)
            val armedKeys = HashSet<String>()
            val toArmKeys = plan.toArm.mapTo(HashSet()) { it.key }
            for (e in plan.selected) {
                if (e.key !in toArmKeys) {
                    armedKeys.add(e.key)
                    continue
                }
                val result = arm(app, am, e, exactOk)
                if (result == ArmResult.FAILED) continue // the entry stays in the store; the next top-up retries
                if (result == ArmResult.INEXACT_NO_PERMISSION) exactOk = false
                armedKeys.add(e.key)
            }

            val stats = AlarmDiff.stats(plan.selected.filter { it.key in armedKeys })
            store.update {
                it.copy(
                    armedCount = stats.armedCount,
                    armedThrough = stats.armedThrough,
                    nextAlarmMs = stats.nextAlarmMs,
                    exactAlarmAllowed = exactOk,
                )
            }
        }
    }

    private enum class ArmResult { EXACT, INEXACT_NO_PERMISSION, INEXACT_OTHER, FAILED }

    /**
     * Task entries (alarm / notification / snooze) use setAlarmClock: never deferred by Doze, it shows the show-intent in the system
     * clock UI, and Android EXEMPTS it from the exact-alarm permission, so task alarms are exact even when "Alarms & reminders" is off
     * (the default on Android 14+). Reminders and the midnight refresh use setExactAndAllowWhileIdle so they do not put a fake "next
     * alarm" in the status bar; that one needs the permission, and without it they fall back to setAndAllowWhileIdle (reported, never
     * an exception).
     */
    private fun arm(app: Context, am: AlarmManager, e: Entry, exactOk: Boolean): ArmResult {
        val pi = PendingIntent.getBroadcast(
            app,
            REQ_ALARM,
            e.putExtras(alarmIntent(app, e.key)),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        var noPermission = !exactOk
        if (Kind.isTaskKind(e.kind)) {
            try {
                am.setAlarmClock(AlarmManager.AlarmClockInfo(e.triggerMs, showPI(app)), pi)
                return ArmResult.EXACT
            } catch (se: SecurityException) {
                noPermission = true
                Log.w(TAG, "alarm clock not permitted, falling back to inexact")
            } catch (t: Throwable) {
                Log.w(TAG, "alarm clock arm failed (${t.javaClass.simpleName}), falling back to inexact")
            }
        } else if (exactOk) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, e.triggerMs, pi)
                return ArmResult.EXACT
            } catch (se: SecurityException) {
                noPermission = true
                Log.w(TAG, "exact alarm not permitted, falling back to inexact")
            } catch (t: Throwable) {
                Log.w(TAG, "exact arm failed (${t.javaClass.simpleName}), falling back to inexact")
            }
        }
        return try {
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, e.triggerMs, pi)
            if (noPermission) ArmResult.INEXACT_NO_PERMISSION else ArmResult.INEXACT_OTHER
        } catch (t: Throwable) {
            Log.e(TAG, "could not arm ${e.kind} entry: ${t.javaClass.simpleName}")
            ArmResult.FAILED
        }
    }

    private fun cancelKey(app: Context, am: AlarmManager, key: String) {
        val pi = lookup(app, key) ?: return
        try {
            am.cancel(pi)
        } catch (_: Exception) {
        }
        pi.cancel()
    }

    private fun isArmed(app: Context, key: String): Boolean = lookup(app, key) != null

    private fun lookup(app: Context, key: String): PendingIntent? =
        PendingIntent.getBroadcast(app, REQ_ALARM, alarmIntent(app, key), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)

    private fun alarmIntent(app: Context, key: String): Intent =
        Intent(app, AlarmReceiver::class.java).setData(Uri.parse("taskrelay://alarm/$key"))

    private fun showPI(app: Context): PendingIntent =
        PendingIntent.getActivity(
            app,
            REQ_SHOW,
            Notifications.openAppIntent(app, "show"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun alarmManager(app: Context) = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
}
