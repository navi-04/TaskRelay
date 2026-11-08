package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.TestFixtures.alarm
import com.naveenraj.taskrelay.TestFixtures.feed
import com.naveenraj.taskrelay.TestFixtures.ms
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId

class FeedPlannerTest {
    private val utc = ZoneId.of("UTC")
    private val noPending = emptySet<TaskDay>()

    // ── the real server example ─────────────────────────────────────────────────────────────────────────────────

    @Test
    fun parsesTheRealFixture() {
        val f = FeedParser.parse(TestFixtures.syncJson())
        assertEquals("W/\"fixture\"", f.version)
        assertEquals("UTC", f.timezone)
        assertEquals(ms("2026-11-06T12:00:00Z"), f.serverTimeMs)
        assertEquals("2026-11-06", f.today.date)
        assertEquals(4, f.today.planned)
        assertEquals(1, f.today.done)
        assertEquals(1, f.today.overdueCount)
        assertEquals(listOf("Team standup", "Gym"), f.today.top)
        assertEquals(4, f.today.tasks.size)
        assertTrue(f.today.tasks[0].done)
        assertFalse(f.today.tasks[1].done)
        assertTrue(f.today.tasks[0].isTop)
        assertEquals("2026-11-19", f.window.coveredUntil)
        assertFalse(f.window.truncated)
        assertEquals(6, f.alarms.size)
        assertEquals("fx-task-gym", f.alarms[0].taskId)
        assertEquals("17:45", f.alarms[0].time) // regenerated fixture: the Gym block starts 18:00 and its reminder is 15 minutes earlier
        assertEquals(Kind.NOTIFICATION, f.alarms[0].kind)
        assertTrue(f.settings.dailyReminderOn)
        assertEquals(9, f.settings.dailyReminderHour)
        assertFalse(f.settings.endOfDayOn)
        assertEquals(21, f.settings.endOfDayHour)
        assertTrue(f.settings.carryOverAlerts)
        assertEquals(480, f.settings.dailyTimeLimitMin)
        assertEquals(10, f.settings.dailyCountLimit)
    }

    @Test
    fun plansTheRealFixture() {
        val f = FeedParser.parse(TestFixtures.syncJson())
        val now = f.serverTimeMs!!
        val plan = FeedPlanner.plan(f, now, utc, noPending, emptyList())
        val byKind = plan.groupBy { it.kind }
        assertEquals(6, byKind.getValue(Kind.NOTIFICATION).size)
        // daily reminder 09:00: today's is already past (12:00 now), so 13 more days
        assertEquals(13, byKind.getValue(Kind.REMINDER_DAILY).size)
        assertNull(byKind[Kind.REMINDER_EOD]) // end_of_day_on is false
        // midnight 00:01 for tomorrow .. today+14
        assertEquals(14, byKind.getValue(Kind.MIDNIGHT).size)
        assertEquals(33, plan.size)
        assertTrue(plan.zipWithNext().all { (a, b) -> a.triggerMs <= b.triggerMs })
        val first = plan.first { it.kind == Kind.NOTIFICATION }
        assertEquals("notification/fx-task-gym/2026-11-06", first.key)
        assertEquals(ms("2026-11-06T17:45:00Z"), first.triggerMs)
        assertEquals("17:45", first.localTime)
        assertEquals("Gym", first.title)
        assertTrue(plan.all { it.triggerMs > now })
    }

    // ── time resolution ─────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun dstGapShiftsForward_newYork() {
        // 2026-03-08 02:30 does not exist in New York (clocks jump 02:00 -> 03:00): it resolves to 03:30 EDT = 07:30Z
        val ny = ZoneId.of("America/New_York")
        val plan = FeedPlanner.plan(feed(listOf(alarm("task-aaaa1", "2026-03-08", "02:30"))), ms("2026-03-01T00:00:00Z"), ny, noPending, emptyList())
        assertEquals(ms("2026-03-08T07:30:00Z"), plan.single { it.kind == Kind.NOTIFICATION }.triggerMs)
    }

    @Test
    fun dstOverlapTakesEarlierOffset_newYork() {
        // 2026-11-01 01:30 happens twice in New York; the earlier one is EDT (UTC-4) = 05:30Z
        val ny = ZoneId.of("America/New_York")
        val plan = FeedPlanner.plan(feed(listOf(alarm("task-aaaa1", "2026-11-01", "01:30"))), ms("2026-10-25T00:00:00Z"), ny, noPending, emptyList())
        assertEquals(ms("2026-11-01T05:30:00Z"), plan.single { it.kind == Kind.NOTIFICATION }.triggerMs)
    }

    @Test
    fun dstGapShiftsForward_london() {
        // 2026-03-29 01:30 does not exist in London (01:00 -> 02:00): it resolves to 02:30 BST = 01:30Z
        val ldn = ZoneId.of("Europe/London")
        val plan = FeedPlanner.plan(feed(listOf(alarm("task-aaaa1", "2026-03-29", "01:30"))), ms("2026-03-20T00:00:00Z"), ldn, noPending, emptyList())
        assertEquals(ms("2026-03-29T01:30:00Z"), plan.single { it.kind == Kind.NOTIFICATION }.triggerMs)
    }

    @Test
    fun dstOverlapTakesEarlierOffset_london() {
        // 2026-10-25 01:30 happens twice in London; the earlier one is BST (UTC+1) = 00:30Z
        val ldn = ZoneId.of("Europe/London")
        val plan = FeedPlanner.plan(feed(listOf(alarm("task-aaaa1", "2026-10-25", "01:30"))), ms("2026-10-20T00:00:00Z"), ldn, noPending, emptyList())
        assertEquals(ms("2026-10-25T00:30:00Z"), plan.single { it.kind == Kind.NOTIFICATION }.triggerMs)
    }

    @Test
    fun malformedAlarmsAreSkippedNotFatal() {
        val plan = FeedPlanner.plan(
            feed(listOf(alarm("task-aaaa1", "2026-13-45", "18:00"), alarm("task-aaaa2", "2026-11-07", "25:99"), alarm("task-aaaa3", "2026-11-07", "18:00"))),
            ms("2026-11-06T12:00:00Z"), utc, noPending, emptyList(),
        )
        assertEquals(listOf("notification/task-aaaa3/2026-11-07"), plan.filter { it.kind == Kind.NOTIFICATION }.map { it.key })
    }

    // ── past instants ───────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun pastInstantsAreDroppedNeverMovedToTomorrow() {
        val f = feed(listOf(alarm("task-aaaa1", "2026-11-06", "08:00"), alarm("task-aaaa2", "2026-11-06", "12:00"), alarm("task-aaaa3", "2026-11-06", "12:01")))
        val plan = FeedPlanner.plan(f, ms("2026-11-06T12:00:00Z"), utc, noPending, emptyList())
        val keys = plan.filter { it.kind == Kind.NOTIFICATION }.map { it.key }
        assertEquals(listOf("notification/task-aaaa3/2026-11-06"), keys) // 08:00 past, 12:00 == now is also dropped
        assertTrue(plan.none { it.key == "notification/task-aaaa1/2026-11-07" })
    }

    // ── determinism ─────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun sameInputGivesIdenticalOutput() {
        val f = FeedParser.parse(TestFixtures.syncJson())
        val now = f.serverTimeMs!!
        val snooze = listOf(TestFixtures.entry(Kind.SNOOZE, "fx-task-gym", "2026-11-06", "12:10", now + 600_000, orig = Kind.ALARM))
        val a = FeedPlanner.plan(f, now, ZoneId.of("Asia/Kolkata"), noPending, snooze)
        val b = FeedPlanner.plan(f, now, ZoneId.of("Asia/Kolkata"), noPending, snooze)
        assertEquals(a, b)
    }

    // ── pending completes ───────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun pendingCompleteRemovesThatOccurrenceOnly() {
        val f = FeedParser.parse(TestFixtures.syncJson())
        val plan = FeedPlanner.plan(f, f.serverTimeMs!!, utc, setOf(TaskDay("fx-task-gym", "2026-11-09")), emptyList())
        val keys = plan.map { it.key }
        assertFalse("notification/fx-task-gym/2026-11-09" in keys)
        assertTrue("notification/fx-task-gym/2026-11-06" in keys)
        assertTrue("notification/fx-task-gym/2026-11-11" in keys)
        assertEquals(32, plan.size)
    }

    // ── reminders ───────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun dailyEodAndMidnightEntries() {
        val s = FeedSettings(dailyReminderOn = true, dailyReminderHour = 7, dailyReminderMin = 30, endOfDayOn = true, endOfDayHour = 21, endOfDayMin = 5)
        val now = ms("2026-11-06T00:00:30Z") // 00:00:30: today's 00:01 midnight is still ahead
        val plan = FeedPlanner.plan(feed(settings = s), now, utc, noPending, emptyList())
        val daily = plan.filter { it.kind == Kind.REMINDER_DAILY }
        val eod = plan.filter { it.kind == Kind.REMINDER_EOD }
        val mid = plan.filter { it.kind == Kind.MIDNIGHT }
        assertEquals(14, daily.size)
        assertEquals(14, eod.size)
        assertEquals(15, mid.size) // today 00:01 through today+14 00:01
        assertEquals("reminder_daily/-/2026-11-06", daily.first().key)
        assertEquals(ms("2026-11-06T07:30:00Z"), daily.first().triggerMs)
        assertEquals("07:30", daily.first().localTime)
        assertEquals("reminder_eod/-/2026-11-19", eod.last().key)
        assertEquals(ms("2026-11-19T21:05:00Z"), eod.last().triggerMs)
        assertEquals("midnight/-/2026-11-06", mid.first().key)
        assertEquals(ms("2026-11-06T00:01:00Z"), mid.first().triggerMs)
        assertEquals("00:01", mid.first().localTime)
        assertTrue(daily.all { it.taskId == null })
    }

    @Test
    fun remindersAreOmittedWhenSwitchedOff() {
        val plan = FeedPlanner.plan(feed(settings = FeedSettings(dailyReminderOn = false, endOfDayOn = false)), ms("2026-11-06T12:00:00Z"), utc, noPending, emptyList())
        assertTrue(plan.none { it.kind == Kind.REMINDER_DAILY || it.kind == Kind.REMINDER_EOD })
        assertEquals(14, plan.count { it.kind == Kind.MIDNIGHT }) // midnight refresh triggers are always planned
    }

    @Test
    fun midnightFollowsTheDeviceZone() {
        val kolkata = ZoneId.of("Asia/Kolkata")
        val now = ms("2026-11-06T12:00:00Z") // 17:30 in Kolkata
        val plan = FeedPlanner.plan(feed(), now, kolkata, noPending, emptyList())
        val first = plan.first { it.kind == Kind.MIDNIGHT }
        assertEquals("midnight/-/2026-11-07", first.key)
        assertEquals(ms("2026-11-06T18:31:00Z"), first.triggerMs) // 2026-11-07 00:01 IST
    }

    // ── snoozes ─────────────────────────────────────────────────────────────────────────────────────────────────

    private val now = ms("2026-11-06T12:00:00Z")
    private fun snooze(task: String, date: String, offsetMs: Long = 600_000) =
        Entry(Entry.keyFor(Kind.SNOOZE, task, date, "1210"), Kind.SNOOZE, task, date, "12:10", "Gym", now + offsetMs, Kind.ALARM)

    @Test
    fun snoozeKeptWhenFeedStillListsTheTaskOpen() {
        val f = feed(listOf(alarm("fx-task-gym", "2026-11-06", "08:00", Kind.ALARM)))
        val s = snooze("fx-task-gym", "2026-11-06")
        val plan = FeedPlanner.plan(f, now, utc, noPending, listOf(s))
        assertTrue(s in plan)
    }

    @Test
    fun snoozeDroppedWhenFeedCoversTheDateButNoLongerListsTheTask() {
        val s = snooze("fx-task-gym", "2026-11-06")
        val plan = FeedPlanner.plan(feed(emptyList()), now, utc, noPending, listOf(s))
        assertFalse(s in plan)
    }

    @Test
    fun snoozeDroppedWhenCompletedLocally() {
        val f = feed(listOf(alarm("fx-task-gym", "2026-11-06", "08:00", Kind.ALARM)))
        val s = snooze("fx-task-gym", "2026-11-06")
        val plan = FeedPlanner.plan(f, now, utc, setOf(TaskDay("fx-task-gym", "2026-11-06")), listOf(s))
        assertFalse(s in plan)
    }

    @Test
    fun snoozeKeptWhenFeedDoesNotCoverItsDate() {
        // yesterday's alarm, snoozed across midnight: the window starts today, so the feed says nothing about it
        val s = snooze("fx-task-gym", "2026-11-05")
        val plan = FeedPlanner.plan(feed(emptyList()), now, utc, noPending, listOf(s))
        assertTrue(s in plan)
    }

    @Test
    fun snoozeOlderThanTheGraceIsDropped() {
        val s = snooze("fx-task-gym", "2026-11-06", offsetMs = -FeedPlanner.PENDING_GRACE_MS - 1)
        val plan = FeedPlanner.plan(feed(listOf(alarm("fx-task-gym", "2026-11-06", "08:00"))), now, utc, noPending, listOf(s))
        assertFalse(s in plan)
    }

    @Test
    fun nonSnoozeEntriesAreNeverRetainedAsSnoozes() {
        val bogus = TestFixtures.entry(Kind.ALARM, "task-bbbb1", "2026-11-06", "13:00", now + 3_600_000)
        val plan = FeedPlanner.plan(feed(emptyList()), now, utc, noPending, listOf(bogus))
        assertTrue(plan.none { it.key == bogus.key })
    }

    // ── carry-over beyond the covered range ─────────────────────────────────────────────────────────────────────

    @Test
    fun entriesBeyondCoveredUntilAreCarriedOverNotCancelled() {
        val stored = listOf(
            TestFixtures.entry(Kind.ALARM, "task-cccc1", "2026-11-15", "09:00", ms("2026-11-15T09:00:00Z")), // beyond covered_until
            TestFixtures.entry(Kind.ALARM, "task-cccc2", "2026-11-10", "09:00", ms("2026-11-10T09:00:00Z")), // inside the range, absent -> gone
        )
        val f = feed(listOf(alarm("task-cccc3", "2026-11-08", "09:00")), to = "2026-11-19", covered = "2026-11-12", truncated = true)
        val plan = FeedPlanner.plan(f, now, utc, noPending, emptyList(), carryOver = stored)
        val keys = plan.map { it.key }
        assertTrue("alarm/task-cccc1/2026-11-15" in keys)
        assertFalse("alarm/task-cccc2/2026-11-10" in keys)
        assertTrue("notification/task-cccc3/2026-11-08" in keys)
    }

    @Test
    fun truncatedFeedAlsoKeepsEntriesOnTheCoveredUntilDay() {
        val stored = listOf(TestFixtures.entry(Kind.ALARM, "task-cccc1", "2026-11-12", "22:00", ms("2026-11-12T22:00:00Z")))
        val f = feed(emptyList(), covered = "2026-11-12", truncated = true)
        assertTrue(FeedPlanner.plan(f, now, utc, noPending, emptyList(), stored).any { it.key == "alarm/task-cccc1/2026-11-12" })
        val complete = feed(emptyList(), covered = "2026-11-12", truncated = false)
        assertFalse(FeedPlanner.plan(complete, now, utc, noPending, emptyList(), stored).any { it.key == "alarm/task-cccc1/2026-11-12" })
    }

    @Test
    fun carriedOverEntryWithPendingCompleteIsDropped() {
        val stored = listOf(TestFixtures.entry(Kind.ALARM, "task-cccc1", "2026-11-15", "09:00", ms("2026-11-15T09:00:00Z")))
        val f = feed(emptyList(), covered = "2026-11-12", truncated = true)
        val plan = FeedPlanner.plan(f, now, utc, setOf(TaskDay("task-cccc1", "2026-11-15")), emptyList(), stored)
        assertTrue(plan.none { it.taskId == "task-cccc1" })
    }

    // ── cap ─────────────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun planIsCappedAt400EntriesKeepingTheNearest() {
        val alarms = (0 until 500).map { i ->
            val minute = i // 00:00 .. 08:19 tomorrow, one alarm per minute
            alarm("task-%05d".format(i), "2026-11-07", "%02d:%02d".format(minute / 60, minute % 60))
        }
        val s = FeedSettings(dailyReminderOn = true, endOfDayOn = true)
        val plan = FeedPlanner.plan(feed(alarms, settings = s), now, utc, noPending, emptyList())
        assertEquals(FeedPlanner.MAX_ENTRIES, plan.size)
        assertEquals(400, plan.size)
        assertTrue(plan.zipWithNext().all { (a, b) -> a.triggerMs <= b.triggerMs })
        // everything that was cut is later than everything that was kept
        val all = FeedPlanner.plan(feed(alarms, settings = s), now, utc, noPending, emptyList()) // determinism again
        assertEquals(all, plan)
        assertTrue(plan.last().triggerMs < ms("2026-11-07T09:00:00Z") + 1) // the 500 alarms end at 08:19, kept range stays near-term
    }

    // ── replan (304 path) ───────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun replanKeepsFutureTaskEntriesDropsPastAndCompletedAndTopsUpReminders() {
        val settings = FeedSettings(dailyReminderOn = true, endOfDayOn = false)
        val stored = listOf(
            TestFixtures.entry(Kind.ALARM, "task-dddd1", "2026-11-06", "18:00", ms("2026-11-06T18:00:00Z")),
            TestFixtures.entry(Kind.ALARM, "task-dddd2", "2026-11-06", "08:00", ms("2026-11-06T08:00:00Z")), // past
            TestFixtures.entry(Kind.NOTIFICATION, "task-dddd3", "2026-11-07", "10:00", ms("2026-11-07T10:00:00Z")), // completed
            TestFixtures.entry(Kind.REMINDER_DAILY, null, "2026-11-07", "09:00", ms("2026-11-07T09:00:00Z")), // regenerated
        )
        val plan = FeedPlanner.replan(stored, settings, now, utc, setOf(TaskDay("task-dddd3", "2026-11-07")))
        val keys = plan.map { it.key }
        assertTrue("alarm/task-dddd1/2026-11-06" in keys)
        assertFalse("alarm/task-dddd2/2026-11-06" in keys)
        assertFalse("notification/task-dddd3/2026-11-07" in keys)
        assertEquals(13, plan.count { it.kind == Kind.REMINDER_DAILY })
        assertEquals(14, plan.count { it.kind == Kind.MIDNIGHT })
    }

    // ── misc ────────────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun entryKeysFollowTheSpecAndRoundTrip() {
        assertEquals("alarm/task-aaaa1/2026-11-06", Entry.keyFor(Kind.ALARM, "task-aaaa1", "2026-11-06"))
        assertEquals("midnight/-/2026-11-07", Entry.keyFor(Kind.MIDNIGHT, null, "2026-11-07"))
        assertEquals("snooze/task-aaaa1/2026-11-06/1210", Entry.keyFor(Kind.SNOOZE, "task-aaaa1", "2026-11-06", "1210"))
        val e = snooze("task-aaaa1", "2026-11-06")
        assertEquals(e, Entry.fromJson(e.toJson()))
        val restored = Entry.fromKey(e.key)
        assertNotNull(restored)
        assertEquals("task-aaaa1", restored!!.taskId)
        assertEquals("12:10", restored.localTime)
        assertEquals(Kind.ALARM, e.ringKind)
        assertEquals(Kind.NOTIFICATION, TestFixtures.entry(Kind.NOTIFICATION, "t", "2026-11-06", "10:00", 1).ringKind)
    }

    // ── alarms that are late but have not fired ─────────────────────────────────────────────────────────────────
    // Without exact-alarm permission Android delivers an inexact alarm up to an hour late. A sync that lands after the nominal time but
    // before delivery used to drop the entry, and the scheduler then cancelled the pending OS alarm: the alarm never rang, silently.

    private val lateAt = ms("2026-11-06T20:37:00Z")
    private val lateKey = Entry.keyFor(Kind.ALARM, "task-late-1", "2026-11-06")
    private fun storedLate(trigger: Long = lateAt) = TestFixtures.entry(Kind.ALARM, "task-late-1", "2026-11-06", "20:37", trigger, "Late")
    private fun lateFeed() = feed(alarms = listOf(alarm("task-late-1", "2026-11-06", "20:37", Kind.ALARM, "Late")))

    @Test
    fun keepsAStoredAlarmWhoseTimePassedButHasNotFiredYet() {
        val plan = FeedPlanner.plan(lateFeed(), lateAt + 56_000, utc, noPending, emptyList(), carryOver = listOf(storedLate()))
        assertEquals(storedLate(), plan.single { it.key == lateKey })
    }

    @Test
    fun neverCreatesAPastAlarmFromTheFeedSoOneThatAlreadyFiredDoesNotRingAgain() {
        // firing removes the entry from the store, so nothing is stored here
        val plan = FeedPlanner.plan(lateFeed(), lateAt + 56_000, utc, noPending, emptyList(), carryOver = emptyList())
        assertTrue(plan.none { it.key == lateKey })
    }

    @Test
    fun givesUpOnAPendingAlarmAfterTheGracePeriod() {
        val now = lateAt + FeedPlanner.PENDING_GRACE_MS + 1_000
        val plan = FeedPlanner.plan(lateFeed(), now, utc, noPending, emptyList(), carryOver = listOf(storedLate()))
        assertTrue(plan.none { it.key == lateKey })
        val justInside = FeedPlanner.plan(lateFeed(), lateAt + FeedPlanner.PENDING_GRACE_MS - 1_000, utc, noPending, emptyList(), carryOver = listOf(storedLate()))
        assertTrue(justInside.any { it.key == lateKey })
    }

    @Test
    fun aPendingAlarmIsDroppedWhenTheTaskLeftTheFeedOrWasCompletedOnThePhone() {
        val now = lateAt + 30_000
        val gone = FeedPlanner.plan(feed(), now, utc, noPending, emptyList(), carryOver = listOf(storedLate())) // deleted / done elsewhere
        assertTrue(gone.none { it.key == lateKey })
        val done = FeedPlanner.plan(lateFeed(), now, utc, setOf(TaskDay("task-late-1", "2026-11-06")), emptyList(), carryOver = listOf(storedLate()))
        assertTrue(done.none { it.key == lateKey })
    }

    @Test
    fun aPendingAlarmIsDroppedWhenItsTimeWasEditedToAnotherInstant() {
        val moved = feed(alarms = listOf(alarm("task-late-1", "2026-11-06", "20:36", Kind.ALARM, "Late"))) // earlier, also past
        val plan = FeedPlanner.plan(moved, lateAt + 30_000, utc, noPending, emptyList(), carryOver = listOf(storedLate()))
        assertTrue(plan.none { it.key == lateKey })
    }

    @Test
    fun keepsAPendingDailyReminderOnlyIfItIsStored() {
        val settings = FeedSettings(dailyReminderOn = true, dailyReminderHour = 9, dailyReminderMin = 0, endOfDayOn = false)
        val nine = ms("2026-11-06T09:00:00Z")
        val key = Entry.keyFor(Kind.REMINDER_DAILY, null, "2026-11-06")
        val stored = TestFixtures.entry(Kind.REMINDER_DAILY, null, "2026-11-06", "09:00", nine, "Daily reminder")
        val now = nine + 10 * 60_000
        assertTrue(FeedPlanner.plan(feed(settings = settings), now, utc, noPending, emptyList(), carryOver = listOf(stored)).any { it.key == key })
        assertTrue(FeedPlanner.plan(feed(settings = settings), now, utc, noPending, emptyList(), carryOver = emptyList()).none { it.key == key })
    }

    @Test
    fun aPendingSnoozeSurvivesAReplan() {
        val snooze = TestFixtures.entry(Kind.SNOOZE, "task-late-1", "2026-11-06", "20:47", lateAt + 10 * 60_000, "Late", orig = Kind.ALARM)
        val plan = FeedPlanner.plan(lateFeed(), lateAt + 10 * 60_000 + 20_000, utc, noPending, listOf(snooze))
        assertTrue(plan.any { it.key == snooze.key })
    }

    @Test
    fun replanKeepsAPendingTaskEntryUntilTheGraceEnds() {
        val kept = FeedPlanner.replan(listOf(storedLate()), null, lateAt + 90_000, utc, noPending)
        assertTrue(kept.any { it.key == lateKey })
        val dropped = FeedPlanner.replan(listOf(storedLate()), null, lateAt + FeedPlanner.PENDING_GRACE_MS + 1_000, utc, noPending)
        assertTrue(dropped.none { it.key == lateKey })
        val completed = FeedPlanner.replan(listOf(storedLate()), null, lateAt + 90_000, utc, setOf(TaskDay("task-late-1", "2026-11-06")))
        assertTrue(completed.none { it.key == lateKey })
    }
}
