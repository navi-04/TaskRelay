package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.BlockerPolicy.Decision
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class BlockerPolicyTest {
    private val utc = ZoneId.of("UTC")

    /** 2026-11-06 is a Friday (ISO 5), 2026-11-08 a Sunday (7), 2026-11-09 a Monday (1). */
    private fun at(iso: String): Long = Instant.parse(iso).toEpochMilli()

    private fun fri(hhmm: String) = at("2026-11-06T$hhmm:00Z")

    private fun config(
        mode: String,
        enabled: Boolean = true,
        countOverdue: Boolean = true,
        unlockWhenDone: Boolean = false,
        windows: List<UseWindow> = emptyList(),
    ) = BlockerConfig(enabled, mode, countOverdue, unlockWhenDone, listOf("com.example.app"), windows)

    private fun day(planned: Int = 4, done: Int = 1, overdue: Int = 1, blocks: List<TodayBlock> = emptyList(), date: String = "2026-11-06") =
        TodayData(date, planned, done, overdue, emptyList(), emptyList(), blocks = blocks)

    private fun block(title: String, start: String, end: String?, duration: Int = 30, done: Boolean = false) =
        TodayBlock("id-$title", title, start, end, duration, done)

    private fun window(start: String, end: String, vararg days: Int) = UseWindow(start, end, days.toList())

    private fun decide(c: BlockerConfig, d: TodayData?, now: Long, zone: ZoneId = utc) = BlockerPolicy.decide(c, d, now, zone)

    // ── off, and failing open ───────────────────────────────────────────────────────────────────────────────────

    @Test
    fun disabledNeverBlocks() {
        for (mode in listOf(BlockerConfig.MODE_UNTIL_DONE, BlockerConfig.MODE_FREE_TIME, BlockerConfig.MODE_SET_TIMES)) {
            assertEquals(Decision(false, BlockCode.OFF), decide(config(mode, enabled = false), day(), fri("10:00")))
        }
        assertEquals(Decision(false, BlockCode.OFF), decide(config(BlockerConfig.MODE_UNTIL_DONE, enabled = false), null, fri("10:00")))
    }

    @Test
    fun noSnapshotFailsOpen() {
        for (mode in listOf(BlockerConfig.MODE_UNTIL_DONE, BlockerConfig.MODE_FREE_TIME, BlockerConfig.MODE_SET_TIMES)) {
            assertEquals(Decision(false, BlockCode.NO_DATA), decide(config(mode), null, fri("10:00")))
        }
    }

    @Test
    fun aStaleOrFutureSnapshotFailsOpen() {
        val c = config(BlockerConfig.MODE_UNTIL_DONE)
        assertEquals(Decision(false, BlockCode.NO_DATA), decide(c, day(date = "2026-11-05"), fri("10:00"))) // yesterday's numbers
        assertEquals(Decision(false, BlockCode.NO_DATA), decide(c, day(date = "2026-11-07"), fri("10:00")))
        assertTrue(decide(c, day(date = "2026-11-06"), fri("10:00")).blocked)
    }

    @Test
    fun todayIsTheDevicesToday() {
        // 23:30 UTC on Friday is already Saturday 05:00 in Kolkata: a Friday snapshot is stale there, fresh in UTC.
        val c = config(BlockerConfig.MODE_UNTIL_DONE)
        val now = at("2026-11-06T23:30:00Z")
        assertTrue(decide(c, day(date = "2026-11-06"), now, utc).blocked)
        assertEquals(BlockCode.NO_DATA, decide(c, day(date = "2026-11-06"), now, ZoneId.of("Asia/Kolkata")).code)
        assertTrue(decide(c, day(date = "2026-11-07"), now, ZoneId.of("Asia/Kolkata")).blocked)
    }

    @Test
    fun theFirstSecondAfterMidnightFailsOpenUntilTheNewDaySyncs() {
        val c = config(BlockerConfig.MODE_FREE_TIME)
        val blocks = listOf(block("Late", "23:30", null, 120)) // [23:30, 24:00)
        assertEquals(BlockCode.TASK_BLOCK, decide(c, day(blocks = blocks), fri("23:59")).code)
        assertEquals(BlockCode.NO_DATA, decide(c, day(blocks = blocks), at("2026-11-07T00:00:00Z")).code)
    }

    // ── until_done ──────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun untilDone_blocksWhileAnythingIsLeft() {
        val d = decide(config(BlockerConfig.MODE_UNTIL_DONE), day(planned = 4, done = 1, overdue = 1), fri("10:00"))
        assertEquals(Decision(true, BlockCode.TASKS_LEFT, left = 3, overdue = 1), d)
    }

    @Test
    fun untilDone_allowsWhenEverythingIsDone() {
        val d = decide(config(BlockerConfig.MODE_UNTIL_DONE), day(planned = 4, done = 4, overdue = 0), fri("10:00"))
        assertEquals(Decision(false, BlockCode.ALL_DONE, left = 0, overdue = 0), d)
    }

    @Test
    fun untilDone_overdueCountsUnlessTurnedOff() {
        val finishedToday = day(planned = 2, done = 2, overdue = 2)
        assertEquals(Decision(true, BlockCode.TASKS_LEFT, left = 0, overdue = 2), decide(config(BlockerConfig.MODE_UNTIL_DONE), finishedToday, fri("10:00")))
        val ignoring = decide(config(BlockerConfig.MODE_UNTIL_DONE, countOverdue = false), finishedToday, fri("10:00"))
        assertEquals(Decision(false, BlockCode.ALL_DONE, left = 0, overdue = 0), ignoring) // overdue is reported as 0 when not counted
    }

    @Test
    fun untilDone_leftIsNeverNegative_andNothingPlannedIsDone() {
        assertEquals(0, decide(config(BlockerConfig.MODE_UNTIL_DONE), day(planned = 2, done = 5, overdue = 0), fri("10:00")).left)
        assertFalse(decide(config(BlockerConfig.MODE_UNTIL_DONE), day(planned = 0, done = 0, overdue = 0), fri("10:00")).blocked)
    }

    @Test
    fun untilDone_ignoresTheClock() {
        val d = decide(config(BlockerConfig.MODE_UNTIL_DONE), day(blocks = listOf(block("Gym", "10:00", "11:00"))), fri("10:30"))
        assertEquals(BlockCode.TASKS_LEFT, d.code)
        assertNull(d.title)
        assertNull(d.nextChangeMin) // nothing on the clock can change it
    }

    // ── free_time ───────────────────────────────────────────────────────────────────────────────────────────────

    private val free = config(BlockerConfig.MODE_FREE_TIME)

    @Test
    fun freeTime_isFreeOutsideBlocks_evenWithTasksLeft() {
        val d = decide(free, day(planned = 4, done = 1, overdue = 1), fri("10:00"))
        assertEquals(Decision(false, BlockCode.FREE_TIME, left = 3, overdue = 1), d)
    }

    @Test
    fun freeTime_aRunningOpenBlockBlocks() {
        val d = decide(free, day(blocks = listOf(block("Gym", "18:00", "19:00"))), fri("18:30"))
        assertEquals(Decision(true, BlockCode.TASK_BLOCK, left = 3, overdue = 1, title = "Gym", untilMin = 1140, nextChangeMin = 1140), d)
    }

    @Test
    fun freeTime_nowEqualsStartBlocks_nowEqualsEndDoesNot() {
        val blocks = listOf(block("Gym", "18:00", "19:00"))
        assertFalse(decide(free, day(blocks = blocks), fri("17:59")).blocked)
        assertTrue(decide(free, day(blocks = blocks), fri("18:00")).blocked)
        assertTrue(decide(free, day(blocks = blocks), fri("18:59")).blocked)
        assertEquals(BlockCode.FREE_TIME, decide(free, day(blocks = blocks), fri("19:00")).code)
    }

    @Test
    fun freeTime_aDoneBlockNeverBlocks() {
        val d = decide(free, day(blocks = listOf(block("Standup", "09:30", "09:45", done = true))), fri("09:35"))
        assertEquals(BlockCode.FREE_TIME, d.code)
        assertNull(d.nextChangeMin) // a done block cannot change anything
    }

    @Test
    fun freeTime_aStartOnlyBlockLastsItsDuration() {
        val blocks = listOf(block("Report", "14:00", null, 90))
        assertTrue(decide(free, day(blocks = blocks), fri("15:29")).blocked)
        assertEquals(930, decide(free, day(blocks = blocks), fri("14:00")).untilMin)
        assertFalse(decide(free, day(blocks = blocks), fri("15:30")).blocked)
    }

    @Test
    fun freeTime_aStartOnlyBlockIsCutAtMidnight() {
        val blocks = listOf(block("Late", "23:30", null, 120))
        val d = decide(free, day(blocks = blocks), fri("23:45"))
        assertTrue(d.blocked)
        assertEquals(1440, d.untilMin)
        assertEquals(1440, d.nextChangeMin)
    }

    @Test
    fun freeTime_anEndAloneOrNoLengthIsNoBlock() {
        // A TodayBlock always has a start; an "end alone" task has none and never reaches the blocks list.
        assertFalse(decide(free, day(blocks = listOf(block("Zero", "10:00", "10:00"))), fri("10:00")).blocked)
        assertFalse(decide(free, day(blocks = listOf(block("NoLength", "10:00", null, 0))), fri("10:00")).blocked)
        assertFalse(decide(free, day(blocks = listOf(block("Backwards", "10:00", "09:00"))), fri("09:30")).blocked)
        assertFalse(decide(free, day(blocks = listOf(block("Garbage", "ten", null, 60))), fri("10:30")).blocked)
    }

    @Test
    fun freeTime_nextChangeIsTheNextBlockStartOrTheRunningBlocksEnd() {
        val blocks = listOf(block("Report", "14:00", null, 90), block("Gym", "18:00", "19:00"))
        assertEquals(840, decide(free, day(blocks = blocks), fri("12:00")).nextChangeMin) // idle: the next start
        assertEquals(930, decide(free, day(blocks = blocks), fri("14:30")).nextChangeMin) // running: its end
        assertEquals(1080, decide(free, day(blocks = blocks), fri("16:00")).nextChangeMin)
        assertNull(decide(free, day(blocks = blocks), fri("19:30")).nextChangeMin) // nothing left today
    }

    @Test
    fun freeTime_overlappingBlocksUntilTheLatestEnd_andOrderDoesNotMatter() {
        val a = block("A", "09:00", "10:00")
        val b = block("B", "09:30", "11:00")
        val d = decide(free, day(blocks = listOf(b, a)), fri("09:45"))
        assertEquals("B", d.title)
        assertEquals(660, d.untilMin)
        assertEquals("B", decide(free, day(blocks = listOf(a, b)), fri("09:45")).title)
    }

    // ── set_times ───────────────────────────────────────────────────────────────────────────────────────────────

    private val evenings = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("18:00", "20:00", 1, 2, 3, 4, 5, 6, 7)))

    @Test
    fun setTimes_blockedOutsideTheWindowAllowedInsideIt_boundariesIncludeStartExcludeEnd() {
        val before = decide(evenings, day(), fri("17:59"))
        assertEquals(Decision(true, BlockCode.OUTSIDE_WINDOWS, left = 3, overdue = 1, nextStartMin = 1080, nextChangeMin = 1080), before)
        val at = decide(evenings, day(), fri("18:00"))
        assertEquals(Decision(false, BlockCode.IN_WINDOW, left = 3, overdue = 1, untilMin = 1200, nextChangeMin = 1200), at)
        assertEquals(BlockCode.IN_WINDOW, decide(evenings, day(), fri("19:59")).code)
        val after = decide(evenings, day(), fri("20:00"))
        assertEquals(BlockCode.OUTSIDE_WINDOWS, after.code)
        assertNull(after.nextStartMin) // no later window today
        assertNull(after.nextChangeMin)
    }

    @Test
    fun setTimes_aRunningTaskBlockBeatsTheUseWindow() {
        val blocks = listOf(block("Call", "18:30", "19:00"))
        val inside = decide(evenings, day(blocks = blocks), fri("18:45"))
        assertEquals(Decision(true, BlockCode.TASK_BLOCK, left = 3, overdue = 1, title = "Call", untilMin = 1140, nextChangeMin = 1140), inside)
        assertEquals(BlockCode.IN_WINDOW, decide(evenings, day(blocks = blocks), fri("19:00")).code) // the window is back as the task ends
        assertEquals(BlockCode.IN_WINDOW, decide(evenings, day(blocks = blocks), fri("18:29")).code)
    }

    @Test
    fun setTimes_aDoneBlockDoesNotBeatTheWindow() {
        val blocks = listOf(block("Call", "18:30", "19:00", done = true))
        assertEquals(BlockCode.IN_WINDOW, decide(evenings, day(blocks = blocks), fri("18:45")).code)
    }

    @Test
    fun setTimes_theWindowEndsWhereTheNextTaskBlockStarts() {
        val blocks = listOf(block("Call", "19:00", "19:30"))
        val d = decide(evenings, day(blocks = blocks), fri("18:10"))
        assertEquals(BlockCode.IN_WINDOW, d.code)
        assertEquals(1140, d.untilMin) // min(window end 20:00, next block start 19:00)
        assertEquals(1140, d.nextChangeMin)
    }

    @Test
    fun setTimes_unlockWhenDoneOpensEverythingOnceNothingIsLeft() {
        val unlocking = config(BlockerConfig.MODE_SET_TIMES, unlockWhenDone = true, windows = listOf(window("18:00", "20:00", 5)))
        val done = day(planned = 4, done = 4, overdue = 0)
        assertEquals(Decision(false, BlockCode.ALL_DONE, left = 0, overdue = 0), decide(unlocking, done, fri("10:00")))
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(unlocking, day(planned = 4, done = 3, overdue = 0), fri("10:00")).code)
        // overdue still counts, unless turned off
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(unlocking, day(planned = 4, done = 4, overdue = 1), fri("10:00")).code)
        val ignoring = config(BlockerConfig.MODE_SET_TIMES, unlockWhenDone = true, countOverdue = false, windows = listOf(window("18:00", "20:00", 5)))
        assertEquals(BlockCode.ALL_DONE, decide(ignoring, day(planned = 4, done = 4, overdue = 1), fri("10:00")).code)
    }

    @Test
    fun setTimes_withoutUnlockWhenDoneFinishingEverythingChangesNothing() {
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(evenings, day(planned = 4, done = 4, overdue = 0), fri("10:00")).code)
    }

    @Test
    fun setTimes_aRunningTaskBlockComesBeforeUnlockWhenDone() {
        val unlocking = config(BlockerConfig.MODE_SET_TIMES, unlockWhenDone = true, windows = listOf(window("18:00", "20:00", 5)))
        val inconsistent = day(planned = 1, done = 1, overdue = 0, blocks = listOf(block("Odd", "10:00", "11:00")))
        assertEquals(BlockCode.TASK_BLOCK, decide(unlocking, inconsistent, fri("10:30")).code) // the rule order is fixed: block first
    }

    @Test
    fun setTimes_windowsFollowTheWeekdayIncludingSunday() {
        val sundays = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("18:00", "20:00", 7)))
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(sundays, day(date = "2026-11-06"), fri("18:30")).code) // Friday
        val sunday = decide(sundays, day(date = "2026-11-08"), at("2026-11-08T18:30:00Z"))
        assertEquals(BlockCode.IN_WINDOW, sunday.code)
        val mondays = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("08:00", "09:00", 1)))
        assertEquals(BlockCode.IN_WINDOW, decide(mondays, day(date = "2026-11-09"), at("2026-11-09T08:30:00Z")).code)
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(mondays, day(date = "2026-11-08"), at("2026-11-08T08:30:00Z")).code) // Sunday
    }

    @Test
    fun setTimes_onlyTodaysWindowsCountForTheNextUseTime() {
        val c = config(
            BlockerConfig.MODE_SET_TIMES,
            windows = listOf(window("12:00", "13:00", 1), window("15:00", "16:00", 5), window("19:00", "20:00", 5)),
        )
        assertEquals(900, decide(c, day(), fri("10:00")).nextStartMin) // Friday: 15:00, not Monday's 12:00
        assertEquals(1140, decide(c, day(), fri("16:30")).nextStartMin)
    }

    @Test
    fun setTimes_anEmptyDaysListMeansEveryDay_andNoWindowsMeansAlwaysBlocked() {
        val everyDay = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(UseWindow("18:00", "20:00", emptyList())))
        assertEquals(BlockCode.IN_WINDOW, decide(everyDay, day(), fri("19:00")).code)
        val none = decide(config(BlockerConfig.MODE_SET_TIMES), day(), fri("19:00"))
        assertEquals(BlockCode.OUTSIDE_WINDOWS, none.code)
        assertNull(none.nextStartMin)
    }

    @Test
    fun setTimes_overlappingWindowsAreAllowedUntilTheLatestEnd() {
        val c = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("18:00", "19:00"), window("18:30", "21:00")))
        assertEquals(1260, decide(c, day(), fri("18:45")).untilMin)
    }

    @Test
    fun setTimes_theLastMinuteOfTheDayIsOutsideAWindowThatEndsAt2359() {
        val c = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("23:00", "23:59")))
        assertEquals(BlockCode.IN_WINDOW, decide(c, day(), fri("23:58")).code)
        assertEquals(BlockCode.OUTSIDE_WINDOWS, decide(c, day(), fri("23:59")).code) // the end is exclusive
    }

    @Test
    fun setTimes_nextChangeCoversBlocksAndWindows() {
        val c = config(BlockerConfig.MODE_SET_TIMES, windows = listOf(window("18:00", "20:00")))
        val blocks = listOf(block("Report", "14:00", null, 90))
        assertEquals(840, decide(c, day(blocks = blocks), fri("10:00")).nextChangeMin) // the block starts first
        assertEquals(930, decide(c, day(blocks = blocks), fri("14:10")).nextChangeMin) // running: its end
        assertEquals(1080, decide(c, day(blocks = blocks), fri("16:00")).nextChangeMin) // then the window opens
    }

    // ── the real contract fixture ───────────────────────────────────────────────────────────────────────────────

    @Test
    fun freeTimeOverTheRealFixtureDay() {
        val today = TodayData.fromFeed(FeedParser.parse(TestFixtures.syncJson()).today, 0L)
        assertEquals(BlockCode.FREE_TIME, decide(free, today, fri("09:35")).code) // standup 09:30-09:45 is done
        val report = decide(free, today, fri("14:30")) // "Write quarterly report", 14:00 + 90 min
        assertEquals(Decision(true, BlockCode.TASK_BLOCK, left = 3, overdue = 1, title = "Write quarterly report", untilMin = 930, nextChangeMin = 930), report)
        assertEquals(BlockCode.FREE_TIME, decide(free, today, fri("16:00")).code)
        val gym = decide(free, today, fri("18:00"))
        assertEquals("Gym", gym.title)
        assertEquals(1140, gym.untilMin)
        assertEquals(BlockCode.FREE_TIME, decide(free, today, fri("19:00")).code)
    }
}
