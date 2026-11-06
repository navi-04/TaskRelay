package com.naveenraj.taskrelay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class TodayAndReminderTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun today(planned: Int = 4, done: Int = 1, overdue: Int = 1, top: List<String> = listOf("Team standup", "Gym"), date: String = "2026-11-06") =
        TodayData(
            date = date,
            planned = planned,
            done = done,
            overdueCount = overdue,
            top = top,
            tasks = listOf(
                TodayTask("fx-task-standup", "Team standup", true, true, 15),
                TodayTask("fx-task-gym", "Gym", false, true, 60),
                TodayTask("fx-task-meditate", "Meditate", false, false, 10),
            ),
        )

    // ── reminder text ───────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun dailyReminderWithTopAndOverdue() {
        val t = ReminderText.daily(today(), "2026-11-06", carryOverAlerts = true)
        assertEquals("Good morning", t.title)
        assertEquals("4 tasks today · Top 3: Team standup, Gym · 1 overdue", t.body)
    }

    @Test
    fun dailyReminderOmitsOverdueWhenSettingOffOrZero() {
        assertEquals("4 tasks today · Top 3: Team standup, Gym", ReminderText.daily(today(), "2026-11-06", false).body)
        assertEquals("4 tasks today · Top 3: Team standup, Gym", ReminderText.daily(today(overdue = 0), "2026-11-06", true).body)
    }

    @Test
    fun dailyReminderOmitsTopWhenNone() {
        assertEquals("2 tasks today · 3 overdue", ReminderText.daily(today(planned = 2, top = emptyList(), overdue = 3), "2026-11-06", true).body)
        assertEquals("1 task today", ReminderText.daily(today(planned = 1, top = emptyList(), overdue = 0), "2026-11-06", true).body)
    }

    @Test
    fun dailyReminderCapsTopAtThree() {
        val body = ReminderText.daily(today(top = listOf("a", "b", "c", "d")), "2026-11-06", false).body
        assertTrue(body.contains("Top 3: a, b, c"))
        assertFalse(body.contains(", d"))
    }

    @Test
    fun dailyReminderNothingPlanned() {
        assertEquals("Nothing planned today", ReminderText.daily(today(planned = 0, done = 0, overdue = 5, top = emptyList()), "2026-11-06", true).body)
    }

    @Test
    fun staleOrMissingCacheNeverShowsYesterdaysNumbers() {
        assertEquals("Open TaskRelay to see today's plan", ReminderText.daily(today(date = "2026-11-05"), "2026-11-06", true).body)
        assertEquals("Open TaskRelay to see today's plan", ReminderText.daily(null, "2026-11-06", true).body)
        assertEquals("Open TaskRelay to review today", ReminderText.endOfDay(null, "2026-11-06").body)
    }

    @Test
    fun endOfDayText() {
        assertEquals("Today: 1 of 4 done · 3 left", ReminderText.endOfDay(today(), "2026-11-06").body)
        assertEquals("Today: 4 of 4 done · Nice work!", ReminderText.endOfDay(today(done = 4), "2026-11-06").body)
        assertEquals("Nothing was planned today", ReminderText.endOfDay(today(planned = 0, done = 0), "2026-11-06").body)
        assertEquals("End of day", ReminderText.endOfDay(today(), "2026-11-06").title)
    }

    // ── cache + pending overlay ─────────────────────────────────────────────────────────────────────────────────

    @Test
    fun completingFlipsTheRowAndCountsOnce() {
        val t = today().withCompleted("fx-task-gym", "2026-11-06")
        assertTrue(t.tasks.first { it.id == "fx-task-gym" }.done)
        assertEquals(2, t.done)
        assertEquals(listOf("fx-task-gym|2026-11-06"), t.pending)
        // idempotent: a second tap changes nothing
        assertEquals(t, t.withCompleted("fx-task-gym", "2026-11-06"))
    }

    @Test
    fun completingADoneTaskOrAnotherDayDoesNotTouchTodaysCounts() {
        val t = today()
        assertEquals(1, t.withCompleted("fx-task-standup", "2026-11-06").done)
        assertEquals(1, t.withCompleted("fx-task-gym", "2026-11-07").done)
        assertEquals(listOf("fx-task-gym|2026-11-07"), t.withCompleted("fx-task-gym", "2026-11-07").pending)
    }

    @Test
    fun doneNeverExceedsPlanned() {
        val t = today(planned = 2, done = 2)
        assertEquals(2, t.withCompleted("fx-task-gym", "2026-11-06").done)
    }

    @Test
    fun pendingOverlayAppliesAfterAFreshFeedSnapshot() {
        val f = FeedParser.parse(TestFixtures.syncJson())
        val fresh = TodayData.fromFeed(f.today, 1L)
        assertEquals(1, fresh.done)
        val overlaid = fresh.withPendingApplied(listOf(TaskDay("fx-task-gym", "2026-11-06"), TaskDay("fx-task-meditate", "2026-11-06")))
        assertEquals(3, overlaid.done)
        assertEquals(setOf("fx-task-gym", "fx-task-meditate", "fx-task-standup"), overlaid.tasks.filter { it.done }.map { it.id }.toSet())
    }

    @Test
    fun cacheKeepsAtMost25Tasks() {
        val many = FeedToday("2026-11-06", 40, 0, 0, emptyList(), (0 until 40).map { FeedTask("task-%05d".format(it), "T$it", false, false, 5) })
        assertEquals(25, TodayData.fromFeed(many, 1L).tasks.size)
    }

    @Test
    fun cacheFileRoundTripAndMarkDone() {
        val cache = TodayCache(File(tmp.root, "today_cache.json"))
        assertNull(cache.read())
        cache.markDone("fx-task-gym", "2026-11-06") // no cache yet: no-op
        assertNull(cache.read())
        val f = FeedParser.parse(TestFixtures.syncJson())
        cache.writeFeed(f.today, 42L) { emptyList() }
        assertEquals(TodayData.fromFeed(f.today, 42L), cache.read())
        cache.markDone("fx-task-gym", "2026-11-06")
        val after = cache.read()!!
        assertTrue(after.tasks.first { it.id == "fx-task-gym" }.done)
        assertEquals(2, after.done)
        // a sync that writes a fresh snapshot while a complete is still unacked keeps the row done
        cache.writeFeed(f.today, 43L) { listOf(TaskDay("fx-task-gym", "2026-11-06")) }
        assertTrue(cache.read()!!.tasks.first { it.id == "fx-task-gym" }.done)
        cache.clear()
        assertNull(cache.read())
    }

    // ── widget state ────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun widgetStates() {
        val signedOut = WidgetState.compute(false, today(), "2026-11-06")
        assertEquals(WidgetState.Mode.SIGNED_OUT, signedOut.mode)
        assertEquals("Sign in to TaskRelay", signedOut.emptyText)
        assertTrue(signedOut.rows.isEmpty())

        val stale = WidgetState.compute(true, today(date = "2026-11-05"), "2026-11-06")
        assertEquals(WidgetState.Mode.STALE, stale.mode)
        assertEquals("Open TaskRelay to refresh", stale.emptyText)
        assertEquals(WidgetState.Mode.STALE, WidgetState.compute(true, null, "2026-11-06").mode)

        val ok = WidgetState.compute(true, today(), "2026-11-06")
        assertEquals(WidgetState.Mode.OK, ok.mode)
        assertEquals("1/4", ok.count)
        assertEquals(3, ok.rows.size)

        val empty = WidgetState.compute(true, today(planned = 0, done = 0).copy(tasks = emptyList()), "2026-11-06")
        assertEquals(WidgetState.Mode.EMPTY, empty.mode)
        assertEquals("Nothing planned today", empty.emptyText)
    }
}
