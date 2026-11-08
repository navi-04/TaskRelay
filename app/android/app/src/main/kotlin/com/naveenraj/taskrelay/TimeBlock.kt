package com.naveenraj.taskrelay

/**
 * PURE: the ONE rule for "when does this task occupy my day". It is the same rule as web/lib/timeblock.ts and the Dart app, and the
 * three test suites share their golden cases:
 *
 *   start + end        -> the block is [start, end]
 *   start only         -> [start, start + duration_min], cut at midnight
 *   end only / neither -> no block (an end alone is a deadline, not a slot you can occupy)
 *
 * Minutes since midnight on the wall clock of the DEVICE's zone; the end is exclusive. A block with no length is no block.
 */
object TimeBlock {
    const val DAY_MIN = 1440

    private val HHMM = Regex("^([01]\\d|2[0-3]):([0-5]\\d)$")

    /** [start, end) in minutes since midnight: start 0..1439, end 1..1440. */
    data class Span(val start: Int, val end: Int) {
        operator fun contains(min: Int): Boolean = min >= start && min < end
    }

    /** "HH:mm" -> minutes since midnight (0..1439); null when it is not exactly that. */
    fun toMinutes(hhmm: String?): Int? {
        val m = HHMM.matchEntire(hhmm ?: return null) ?: return null
        return m.groupValues[1].toInt() * 60 + m.groupValues[2].toInt()
    }

    /** The block of a task with these fields, or null when it has none. */
    fun of(startTime: String?, endTime: String?, durationMin: Int): Span? {
        val start = toMinutes(startTime) ?: return null
        val end = if (endTime.isNullOrEmpty()) {
            minOf(start.toLong() + durationMin, DAY_MIN.toLong()).toInt() // Long: a huge duration must not overflow
        } else {
            toMinutes(endTime) ?: return null
        }
        return if (end > start) Span(start, end) else null
    }
}
