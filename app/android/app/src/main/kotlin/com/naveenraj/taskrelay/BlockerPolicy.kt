package com.naveenraj.taskrelay

import java.time.Instant
import java.time.ZoneId

/** Why the blocker decided what it decided ([BlockerPolicy.Decision.code]). */
object BlockCode {
    const val OFF = "off"
    const val NO_DATA = "no_data"
    const val ALL_DONE = "all_done"
    const val FREE_TIME = "free_time"
    const val IN_WINDOW = "in_window"
    const val TASKS_LEFT = "tasks_left"
    const val TASK_BLOCK = "task_block"
    const val OUTSIDE_WINDOWS = "outside_windows"
}

/**
 * PURE: should a blocked-list app be stopped right now? No Android, no clock, no I/O: the caller injects the config, the cached
 * day, the instant and the zone, so every rule is unit-tested on the JVM.
 *
 * FAILS OPEN: with the blocker off, or with no snapshot of TODAY (never synced, or yesterday's), nothing is blocked. Missing or stale
 * data must never lock the user out of their phone.
 *
 * Modes (config.mode):
 *  - until_done: blocked while anything is left today (plus overdue, if counted);
 *  - free_time:  blocked only while one of today's OPEN time blocks is running; the rest of the day is free;
 *  - set_times:  a running open time block blocks FIRST (a use window never overrides a task); then, if `unlock_when_done` and
 *                nothing is left, allowed; then allowed inside a use window of today's weekday; otherwise blocked.
 * A done block never blocks. Times are minutes since midnight in [zone]; a block or window includes its start and not its end.
 */
object BlockerPolicy {

    /**
     * @property left today's unfinished tasks (planned - done, never negative); the cache already holds pending local completes
     * @property overdue overdue tasks, counted only when `count_overdue` is on (else 0)
     * @property title the running time block's title (code `task_block`)
     * @property untilMin minute of day the current block / use window ends (`task_block`, `in_window`)
     * @property nextStartMin start of the next use window later today (`outside_windows`)
     * @property nextChangeMin the next minute of day at which the decision can change from the clock alone (a block or window
     *   start or end); null when nothing on the clock can change it
     */
    data class Decision(
        val blocked: Boolean,
        val code: String,
        val left: Int = 0,
        val overdue: Int = 0,
        val title: String? = null,
        val untilMin: Int? = null,
        val nextStartMin: Int? = null,
        val nextChangeMin: Int? = null,
    ) {
        /** The channel shape (`blockerStatus.decision`). */
        fun toMap(): Map<String, Any?> = mapOf(
            "blocked" to blocked,
            "code" to code,
            "left" to left,
            "overdue" to overdue,
            "title" to title,
            "until_min" to untilMin,
            "next_start_min" to nextStartMin,
            "next_change_min" to nextChangeMin,
        )
    }

    private class OpenBlock(val title: String, val span: TimeBlock.Span)

    fun decide(config: BlockerConfig, today: TodayData?, nowMs: Long, zone: ZoneId): Decision {
        if (!config.enabled) return Decision(false, BlockCode.OFF)
        val local = Instant.ofEpochMilli(nowMs).atZone(zone)
        if (today == null || today.date != local.toLocalDate().toString()) return Decision(false, BlockCode.NO_DATA)

        val nowMin = local.hour * 60 + local.minute
        val left = maxOf(0, today.planned - today.done)
        val overdue = if (config.countOverdue) maxOf(0, today.overdueCount) else 0
        val blocks = today.blocks.filter { !it.done }.mapNotNull { b -> b.span?.let { OpenBlock(b.title, it) } }
        val running = blocks.filter { nowMin in it.span }.maxWithOrNull(compareBy<OpenBlock> { it.span.end }.thenBy { -it.span.start })

        // The decision for a running block, shared by free_time and set_times.
        fun taskBlock(r: OpenBlock, windows: List<TimeBlock.Span>) =
            Decision(true, BlockCode.TASK_BLOCK, left, overdue, title = r.title, untilMin = r.span.end, nextChangeMin = nextChange(nowMin, blocks, windows))

        return when (config.mode) {
            BlockerConfig.MODE_FREE_TIME ->
                if (running != null) taskBlock(running, emptyList())
                else Decision(false, BlockCode.FREE_TIME, left, overdue, nextChangeMin = nextChange(nowMin, blocks, emptyList()))

            BlockerConfig.MODE_SET_TIMES -> {
                val windows = config.windows.filter { it.appliesOn(local.dayOfWeek.value) }.mapNotNull { it.span }
                when {
                    running != null -> taskBlock(running, windows)
                    config.unlockWhenDone && left + overdue == 0 ->
                        Decision(false, BlockCode.ALL_DONE, left, overdue, nextChangeMin = nextChange(nowMin, blocks, emptyList()))
                    else -> {
                        val inside = windows.filter { nowMin in it }.maxByOrNull { it.end }
                        val change = nextChange(nowMin, blocks, windows)
                        if (inside != null) {
                            val nextBlockStart = blocks.map { it.span.start }.filter { it > nowMin }.minOrNull()
                            Decision(false, BlockCode.IN_WINDOW, left, overdue, untilMin = minOf(inside.end, nextBlockStart ?: inside.end), nextChangeMin = change)
                        } else {
                            Decision(true, BlockCode.OUTSIDE_WINDOWS, left, overdue, nextStartMin = windows.map { it.start }.filter { it > nowMin }.minOrNull(), nextChangeMin = change)
                        }
                    }
                }
            }

            // until_done, and anything unknown (a normalised config never has one)
            else ->
                if (left + overdue == 0) Decision(false, BlockCode.ALL_DONE, left, overdue)
                else Decision(true, BlockCode.TASKS_LEFT, left, overdue)
        }
    }

    /** The earliest start or end after [nowMin] among the open blocks and the windows that apply today; null when there is none. */
    private fun nextChange(nowMin: Int, blocks: List<OpenBlock>, windows: List<TimeBlock.Span>): Int? =
        (blocks.flatMap { listOf(it.span.start, it.span.end) } + windows.flatMap { listOf(it.start, it.end) })
            .filter { it > nowMin }
            .minOrNull()
}
