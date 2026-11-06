package com.naveenraj.taskrelay

/**
 * PURE diff / selection logic behind AlarmScheduler (no Android classes, JVM-testable).
 *
 * Android caps an app at roughly 500 pending alarms, so only the NEAREST [MAX_ARMED] future entries are armed; the rest stay
 * in the store and are armed later as time passes ("top up", done by rearmFromStore after boot / every fire / every apply).
 */
object AlarmDiff {
    const val MAX_ARMED = 100

    data class ArmPlan(
        /** The entries that should be armed after this pass (nearest first). */
        val selected: List<Entry>,
        /** The subset of [selected] that must be (re)armed now: new, changed, or not currently registered. */
        val toArm: List<Entry>,
        /** Stored keys that must be unregistered: disappeared from the plan, already past, or pushed beyond the arming cap. */
        val toCancel: List<String>,
    )

    /** The nearest [limit] entries strictly after [nowMs], ordered by trigger time then key. */
    fun selectNearest(entries: List<Entry>, nowMs: Long, limit: Int = MAX_ARMED): List<Entry> =
        entries.asSequence()
            .filter { it.triggerMs > nowMs }
            .sortedWith(FeedPlanner.ORDER)
            .take(limit)
            .toList()

    /** A key is a no-op when its trigger time and title are unchanged. */
    fun isUnchanged(stored: Entry?, planned: Entry): Boolean =
        stored != null && stored.triggerMs == planned.triggerMs && stored.title == planned.title

    /**
     * @param stored the entries currently in the store (what was armed last time)
     * @param planned the desired set
     * @param isArmed whether the OS currently holds a registration for a key (probed only for unchanged keys)
     */
    fun compute(
        stored: List<Entry>,
        planned: List<Entry>,
        nowMs: Long,
        limit: Int = MAX_ARMED,
        isArmed: (String) -> Boolean,
    ): ArmPlan {
        val storedByKey = stored.associateBy { it.key }
        val selected = selectNearest(planned, nowMs, limit)
        val selectedKeys = selected.mapTo(HashSet()) { it.key }
        val toArm = selected.filter { !isUnchanged(storedByKey[it.key], it) || !isArmed(it.key) }
        val toCancel = stored.map { it.key }.filter { it !in selectedKeys }
        return ArmPlan(selected, toArm, toCancel)
    }

    /** Stats the UI shows: task-bearing entries only (alarm / notification / snooze), reminders and midnight triggers excluded. */
    data class Stats(val armedCount: Int, val armedThrough: String?, val nextAlarmMs: Long?)

    fun stats(armed: List<Entry>): Stats {
        val task = armed.filter { Kind.isTaskKind(it.kind) }
        return Stats(
            armedCount = task.size,
            armedThrough = task.maxWithOrNull(FeedPlanner.ORDER)?.date,
            nextAlarmMs = task.minOfOrNull { it.triggerMs },
        )
    }
}
