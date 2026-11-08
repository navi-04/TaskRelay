package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.BlockerPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockerTextTest {
    private fun tasksLeft(left: Int, overdue: Int = 0) = Decision(true, BlockCode.TASKS_LEFT, left, overdue)

    @Test
    fun hhmmFormatsMinutesSinceMidnight() {
        assertEquals("00:00", BlockerText.hhmm(0))
        assertEquals("09:05", BlockerText.hhmm(545))
        assertEquals("18:00", BlockerText.hhmm(1080))
        assertEquals("23:59", BlockerText.hhmm(1439))
        assertEquals("00:00", BlockerText.hhmm(1440)) // the end of the day reads as midnight
    }

    @Test
    fun hhmmFollowsTheTwelveHourStyleOfThePhone() {
        assertEquals("12:00 AM", BlockerText.hhmm(0, use24h = false))
        assertEquals("9:05 AM", BlockerText.hhmm(545, use24h = false))
        assertEquals("12:00 PM", BlockerText.hhmm(720, use24h = false))
        assertEquals("12:30 PM", BlockerText.hhmm(750, use24h = false))
        assertEquals("6:00 PM", BlockerText.hhmm(1080, use24h = false))
        assertEquals("11:59 PM", BlockerText.hhmm(1439, use24h = false))
        assertEquals("12:00 AM", BlockerText.hhmm(1440, use24h = false)) // the end of the day
    }

    @Test
    fun reasonsUseThePhonesClockStyle() {
        val block = Decision(true, BlockCode.TASK_BLOCK, title = "Gym", untilMin = 1140)
        assertEquals("\"Gym\" runs until 7:00 PM", BlockerText.reason(block, use24h = false))
        assertEquals("\"Gym\" runs until 19:00", BlockerText.reason(block)) // 24-hour stays the default
        assertEquals("Next use time: 6:00 PM", BlockerText.reason(Decision(true, BlockCode.OUTSIDE_WINDOWS, nextStartMin = 1080), use24h = false))
        assertEquals("Next use time: 6:00 PM", BlockerText.screen("Chrome", Decision(true, BlockCode.OUTSIDE_WINDOWS, nextStartMin = 1080), false, null, use24h = false).reason)
    }

    @Test
    fun tasksLeftReason() {
        assertEquals("3 tasks left today", BlockerText.reason(tasksLeft(3)))
        assertEquals("1 task left today", BlockerText.reason(tasksLeft(1)))
        assertEquals("3 tasks left today and 2 overdue", BlockerText.reason(tasksLeft(3, 2)))
        assertEquals("1 task left today and 1 overdue", BlockerText.reason(tasksLeft(1, 1)))
        assertEquals("0 tasks left today and 2 overdue", BlockerText.reason(tasksLeft(0, 2)))
    }

    @Test
    fun taskBlockReason() {
        val d = Decision(true, BlockCode.TASK_BLOCK, title = "Gym", untilMin = 1140)
        assertEquals("\"Gym\" runs until 19:00", BlockerText.reason(d))
        assertEquals("\"Late\" runs until 00:00", BlockerText.reason(d.copy(title = "Late", untilMin = 1440)))
        assertEquals("Your task block runs until 19:00", BlockerText.reason(d.copy(title = "")))
        assertEquals("\"Gym\" is running now", BlockerText.reason(d.copy(untilMin = null)))
    }

    @Test
    fun outsideWindowsReason() {
        assertEquals("Next use time: 18:00", BlockerText.reason(Decision(true, BlockCode.OUTSIDE_WINDOWS, nextStartMin = 1080)))
        assertEquals("No use times set for now", BlockerText.reason(Decision(true, BlockCode.OUTSIDE_WINDOWS)))
    }

    @Test
    fun allowedDecisionsHaveNothingToExplain() {
        for (code in listOf(BlockCode.OFF, BlockCode.NO_DATA, BlockCode.ALL_DONE, BlockCode.FREE_TIME, BlockCode.IN_WINDOW)) {
            assertEquals("", BlockerText.reason(Decision(false, code)))
        }
    }

    @Test
    fun headline() {
        assertEquals("Instagram is blocked", BlockerText.headline("Instagram"))
        assertEquals("This app is blocked", BlockerText.headline(null))
        assertEquals("This app is blocked", BlockerText.headline("  "))
        assertEquals("Chat is blocked", BlockerText.headline("Chat 💬")) // no emoji on the block screen
    }

    @Test
    fun nextTasksListsUpToThreeOpenTitles() {
        val tasks = listOf(
            TodayTask("t1", "Team standup", true, true, 15), // done: not listed
            TodayTask("t2", "Gym", false, true, 60),
            TodayTask("t3", "Write quarterly report", false, false, 90),
            TodayTask("t4", "  ", false, false, 5), // blank: not listed
            TodayTask("t5", "Meditate", false, false, 10),
            TodayTask("t6", "Fourth open one", false, false, 10),
        )
        val today = TodayData("2026-11-06", 6, 1, 0, emptyList(), tasks)
        assertEquals("Next: Gym, Write quarterly report, Meditate", BlockerText.nextTasks(today))
        assertNull(BlockerText.nextTasks(null))
        assertNull(BlockerText.nextTasks(today.copy(tasks = tasks.take(1))))
    }

    @Test
    fun longTitlesAreShortened() {
        val title = "x".repeat(60)
        val today = TodayData("2026-11-06", 1, 0, 0, emptyList(), listOf(TodayTask("t1", title, false, false, 5)))
        assertEquals("Next: " + "x".repeat(40) + "...", BlockerText.nextTasks(today))
        val d = Decision(true, BlockCode.TASK_BLOCK, title = title, untilMin = 600)
        assertEquals("\"" + "x".repeat(40) + "...\" runs until 10:00", BlockerText.reason(d))
    }

    @Test
    fun screenCombinesTheLines_andListsTasksOnlyWhileTasksAreLeft() {
        val today = TodayData("2026-11-06", 2, 0, 0, emptyList(), listOf(TodayTask("t1", "Gym", false, true, 60)))
        val s = BlockerText.screen("Instagram", tasksLeft(2), unlockWhenDone = false, today = today)
        assertEquals(BlockScreen("Instagram is blocked", "2 tasks left today", "Next: Gym", true), s)
        val block = BlockerText.screen("Instagram", Decision(true, BlockCode.TASK_BLOCK, title = "Gym", untilMin = 1140), false, today)
        assertNull(block.next)
        assertEquals("\"Gym\" runs until 19:00", block.reason)
    }

    @Test
    fun checkAgainOnlyWhereFreshDataCanChangeTheAnswer() {
        assertTrue(BlockerText.canCheckAgain(tasksLeft(2), unlockWhenDone = false))
        assertTrue(BlockerText.canCheckAgain(Decision(true, BlockCode.TASK_BLOCK, title = "Gym", untilMin = 1140), unlockWhenDone = false))
        val outside = Decision(true, BlockCode.OUTSIDE_WINDOWS, nextStartMin = 1080)
        assertFalse(BlockerText.canCheckAgain(outside, unlockWhenDone = false)) // only the clock opens it
        assertTrue(BlockerText.canCheckAgain(outside, unlockWhenDone = true)) // finishing everything would
        assertFalse(BlockerText.canCheckAgain(Decision(false, BlockCode.ALL_DONE), unlockWhenDone = true))
    }

    // ── the block screen is plain text only ─────────────────────────────────────────────────────────────────────

    @Test
    fun plainRemovesEmojiPictographsAndTheirJoiners() {
        assertEquals("Gym", BlockerText.plain("Gym 💪")) // flexed biceps
        assertEquals("Pay rent", BlockerText.plain("💸 Pay rent")) // money with wings
        assertEquals("Pride", BlockerText.plain("🏳️‍🌈 Pride")) // rainbow flag: ZWJ sequence
        assertEquals("Love", BlockerText.plain("Love ❤️")) // red heart with variation selector
        assertEquals("Done", BlockerText.plain("✅ Done")) // check mark button
        assertEquals("Wake up", BlockerText.plain("Wake up ⏰")) // alarm clock
        assertEquals("A B", BlockerText.plain("A  😀😀   B")) // whitespace collapses
    }

    @Test
    fun plainKeepsOrdinaryTextIncludingOtherScripts() {
        assertEquals("Call Dr. O'Neil at 5pm (urgent) - 50% off", BlockerText.plain("Call Dr. O'Neil at 5pm (urgent) - 50% off"))
        assertEquals("Café Müller © 2026", BlockerText.plain("Café Müller © 2026"))
        assertEquals("இன்று கூட்டம்", BlockerText.plain("இன்று கூட்டம்")) // Tamil
        assertEquals("会议", BlockerText.plain("会议")) // CJK
        assertEquals("क्‍ष", BlockerText.plain("क्‍ष")) // Devanagari: a joiner between letters stays
        assertEquals("a‌b", BlockerText.plain("a‌b")) // zero-width non-joiner (Persian) stays
        assertEquals("", BlockerText.plain(""))
    }

    @Test
    fun everyFixedStringOnTheScreenIsPlainAscii() {
        val fixed = listOf(
            BlockerText.OPEN_APP, BlockerText.CHECK_AGAIN, BlockerText.CHECKING, BlockerText.CLOSE,
            BlockerText.CHECKED_UNCHANGED, BlockerText.CHECK_FAILED,
            BlockerText.reason(tasksLeft(3, 2)),
            BlockerText.reason(Decision(true, BlockCode.TASK_BLOCK, title = "Gym", untilMin = 1140)),
            BlockerText.reason(Decision(true, BlockCode.OUTSIDE_WINDOWS, nextStartMin = 1080)),
            BlockerText.reason(Decision(true, BlockCode.OUTSIDE_WINDOWS)),
            BlockerText.headline("Instagram"),
        )
        for (s in fixed) assertTrue(s, s.all { it.code in 0x20..0x7E }) // nothing that Android could draw in colour
    }
}
