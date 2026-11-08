package com.naveenraj.taskrelay

/** What the block screen shows. [next] is the "Next: A, B, C" line (null when there is nothing to list). */
data class BlockScreen(val headline: String, val reason: String, val next: String?, val canCheckAgain: Boolean)

/**
 * PURE: the words on the block screen. The screen is strictly black and white, so everything here is plain text: no symbols, and the
 * pictographs / emoji a task title may contain are removed ([plain]) because Android would draw them in colour.
 */
object BlockerText {
    const val OPEN_APP = "Open TaskRelay"
    const val CHECK_AGAIN = "Check again"
    const val CHECKING = "Checking..."
    const val CLOSE = "Close"
    const val CHECKED_UNCHANGED = "Checked just now. Nothing has changed."
    const val CHECK_FAILED = "Could not check right now."

    private const val MAX_TITLE_CHARS = 40
    private const val MAX_NEXT_TASKS = 3
    private val WHITESPACE = Regex("\\s+")

    /** [use24h]: the phone's clock style (the app shows "6:00 PM" on a 12-hour phone, so the block screen does too). */
    fun screen(appLabel: String?, d: BlockerPolicy.Decision, unlockWhenDone: Boolean, today: TodayData?, use24h: Boolean = true): BlockScreen =
        BlockScreen(headline(appLabel), reason(d, use24h), if (d.code == BlockCode.TASKS_LEFT) nextTasks(today) else null, canCheckAgain(d, unlockWhenDone))

    /** "<App label> is blocked". */
    fun headline(appLabel: String?): String = "${plain(appLabel.orEmpty()).ifEmpty { "This app" }} is blocked"

    /** One line saying why. Empty for a decision that does not block (nothing to explain). */
    fun reason(d: BlockerPolicy.Decision, use24h: Boolean = true): String = when (d.code) {
        BlockCode.TASKS_LEFT -> {
            val left = if (d.left == 1) "1 task left today" else "${d.left} tasks left today"
            if (d.overdue > 0) "$left and ${d.overdue} overdue" else left
        }
        BlockCode.TASK_BLOCK -> {
            val title = shorten(plain(d.title.orEmpty()))
            val subject = if (title.isEmpty()) "Your task block" else "\"$title\""
            d.untilMin?.let { "$subject runs until ${hhmm(it, use24h)}" } ?: "$subject is running now"
        }
        BlockCode.OUTSIDE_WINDOWS -> d.nextStartMin?.let { "Next use time: ${hhmm(it, use24h)}" } ?: "No use times set for now"
        else -> ""
    }

    /** "Next: A, B, C": up to three open tasks of today, in the cache's order; null when there are none. */
    fun nextTasks(today: TodayData?): String? {
        val titles = today?.tasks.orEmpty().filter { !it.done }.map { shorten(plain(it.title)) }.filter { it.isNotEmpty() }.take(MAX_NEXT_TASKS)
        return if (titles.isEmpty()) null else "Next: " + titles.joinToString(", ")
    }

    /**
     * "Check again" (a sync) only makes sense where fresh data can change the answer: always while tasks are left or a task block
     * runs; outside the use windows only when finishing everything unlocks.
     */
    fun canCheckAgain(d: BlockerPolicy.Decision, unlockWhenDone: Boolean): Boolean =
        d.blocked && (d.code != BlockCode.OUTSIDE_WINDOWS || unlockWhenDone)

    /** Minutes since midnight as "HH:mm" (or "6:00 PM" when [use24h] is false); 1440 (the end of the day) reads "00:00" / "12:00 AM". */
    fun hhmm(min: Int, use24h: Boolean = true): String {
        val m = Math.floorMod(min, TimeBlock.DAY_MIN)
        val h = m / 60
        if (use24h) return Times.hhmm(h, m % 60)
        val h12 = if (h % 12 == 0) 12 else h % 12
        return "$h12:${(m % 60).toString().padStart(2, '0')} ${if (h < 12) "AM" else "PM"}"
    }

    /**
     * [s] without emoji and pictographs, their variation selectors and keycap marks, and the zero-width joiners that glue them
     * together (a joiner between letters of an Indic script stays); whitespace collapsed and trimmed.
     */
    fun plain(s: String): String {
        val cps = ArrayList<Int>(s.length)
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            cps.add(cp)
            i += Character.charCount(cp)
        }
        val sb = StringBuilder(s.length)
        for ((n, cp) in cps.withIndex()) {
            val drop = when (cp) {
                0xFE0F, 0x20E3 -> true // emoji variation selector, combining keycap
                0x200D -> (n > 0 && isPictograph(cps[n - 1])) || (n + 1 < cps.size && isPictograph(cps[n + 1])) // joiner of an emoji sequence
                else -> isPictograph(cp)
            }
            if (!drop) sb.appendCodePoint(cp)
        }
        return sb.toString().replace(WHITESPACE, " ").trim()
    }

    private fun shorten(s: String): String = if (s.length <= MAX_TITLE_CHARS) s else s.take(MAX_TITLE_CHARS).trimEnd() + "..."

    private fun isPictograph(cp: Int): Boolean =
        cp in 0x1F000..0x1FFFF || // emoji, flags, pictographs, symbols
            cp in 0x2300..0x23FF || // watch, hourglass, keyboard ...
            cp in 0x2600..0x27BF || // misc symbols and dingbats (sun, check marks, hearts ...)
            cp in 0x2B00..0x2BFF || // arrows, stars, squares
            cp in 0x2934..0x2935 || cp in 0x25FD..0x25FE ||
            cp == 0x3030 || cp == 0x303D || cp == 0x3297 || cp == 0x3299 ||
            cp in 0xE0020..0xE007F // tag characters of subdivision flags
}
