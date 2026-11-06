package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.TestFixtures.entry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class AlarmDiffTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val now = 1_000_000L
    private val armedEverything: (String) -> Boolean = { true }
    private val armedNothing: (String) -> Boolean = { false }

    private fun alarm(id: String, trigger: Long, title: String = "t") =
        Entry(Entry.keyFor(Kind.ALARM, id, "2026-11-06"), Kind.ALARM, id, "2026-11-06", "10:00", title, trigger)

    @Test
    fun unchangedKeyIsANoOp() {
        val e = alarm("task-aaaa1", now + 100)
        val plan = AlarmDiff.compute(listOf(e), listOf(e.copy()), now, isArmed = armedEverything)
        assertTrue(plan.toArm.isEmpty())
        assertTrue(plan.toCancel.isEmpty())
        assertEquals(listOf(e), plan.selected)
    }

    @Test
    fun changedTriggerOrTitleIsRearmed() {
        val old = alarm("task-aaaa1", now + 100, "Gym")
        assertEquals(listOf(old.copy(triggerMs = now + 200)), AlarmDiff.compute(listOf(old), listOf(old.copy(triggerMs = now + 200)), now, isArmed = armedEverything).toArm)
        assertEquals(listOf(old.copy(title = "Gym 2")), AlarmDiff.compute(listOf(old), listOf(old.copy(title = "Gym 2")), now, isArmed = armedEverything).toArm)
    }

    @Test
    fun newKeyIsArmed() {
        val a = alarm("task-aaaa1", now + 100)
        val b = alarm("task-bbbb2", now + 200)
        val plan = AlarmDiff.compute(listOf(a), listOf(a, b), now, isArmed = armedEverything)
        assertEquals(listOf(b), plan.toArm)
        assertTrue(plan.toCancel.isEmpty())
    }

    @Test
    fun removedKeyIsCancelledAndNothingElseIs() {
        val a = alarm("task-aaaa1", now + 100)
        val b = alarm("task-bbbb2", now + 200)
        val plan = AlarmDiff.compute(listOf(a, b), listOf(b), now, isArmed = armedEverything)
        assertEquals(listOf(a.key), plan.toCancel)
        assertTrue(plan.toArm.isEmpty())
    }

    @Test
    fun unchangedButNotRegisteredWithTheOsIsArmedAgain() {
        // e.g. after a force-stop or reboot wiped the PendingIntents: the store says unchanged, the OS disagrees
        val e = alarm("task-aaaa1", now + 100)
        val plan = AlarmDiff.compute(listOf(e), listOf(e), now, isArmed = armedNothing)
        assertEquals(listOf(e), plan.toArm)
    }

    @Test
    fun isArmedIsOnlyProbedForUnchangedKeys() {
        val changed = alarm("task-aaaa1", now + 100)
        val same = alarm("task-bbbb2", now + 200)
        val probed = mutableListOf<String>()
        AlarmDiff.compute(listOf(changed.copy(triggerMs = now + 1), same), listOf(changed, same), now) { probed.add(it); true }
        assertEquals(listOf(same.key), probed)
    }

    @Test
    fun onlyTheNearest100FutureEntriesAreSelected() {
        val planned = (0 until 250).map { i -> alarm("task-%05d".format(i), now + 1000L * (250 - i)) } // inserted far-to-near
        val plan = AlarmDiff.compute(emptyList(), planned, now, isArmed = armedNothing)
        assertEquals(100, plan.selected.size)
        assertEquals(100, plan.toArm.size)
        val expected = planned.sortedBy { it.triggerMs }.take(100)
        assertEquals(expected, plan.selected)
        assertTrue(plan.selected.zipWithNext().all { (a, b) -> a.triggerMs < b.triggerMs })
    }

    @Test
    fun pastEntriesAreNeverSelected() {
        val past = alarm("task-aaaa1", now - 1)
        val equalNow = alarm("task-bbbb2", now)
        val future = alarm("task-cccc3", now + 1)
        val plan = AlarmDiff.compute(emptyList(), listOf(past, equalNow, future), now, isArmed = armedNothing)
        assertEquals(listOf(future), plan.selected)
    }

    @Test
    fun entriesPushedBeyondTheCapAreUnregisteredAndComeBackLater() {
        val stored = (0 until 100).map { i -> alarm("task-%05d".format(i), now + 1000L * (i + 1)) }
        val nearer = alarm("task-nearr", now + 1) // a new, nearer alarm pushes the farthest one out of the nearest 100
        val plan = AlarmDiff.compute(stored, stored + nearer, now, isArmed = armedEverything)
        assertEquals(listOf(nearer), plan.toArm)
        assertEquals(listOf(stored.last().key), plan.toCancel)
        // once the nearer one has fired and is gone, the pushed-out entry is selected (and armed) again: the top-up
        val later = AlarmDiff.compute(stored + nearer, stored, now + 2, isArmed = { it != stored.last().key })
        assertEquals(listOf(stored.last()), later.toArm)
    }

    @Test
    fun staleStoredEntriesPastTheGraceAreCancelled() {
        // (an entry only a moment past its time is NOT stale: see doesNotCancelAnEntryThatIsPastItsTimeButStillPlanned)
        val past = alarm("task-aaaa1", now - FeedPlanner.PENDING_GRACE_MS - 10)
        val future = alarm("task-bbbb2", now + 10)
        val plan = AlarmDiff.compute(listOf(past, future), listOf(past, future), now, isArmed = armedEverything)
        assertEquals(listOf(past.key), plan.toCancel)
    }

    @Test
    fun statsCountTaskEntriesOnly() {
        val armed = listOf(
            entry(Kind.REMINDER_DAILY, null, "2026-11-07", "09:00", 50),
            Entry(Entry.keyFor(Kind.ALARM, "task-aaaa1", "2026-11-08"), Kind.ALARM, "task-aaaa1", "2026-11-08", "10:00", "t", 300),
            Entry(Entry.keyFor(Kind.NOTIFICATION, "task-bbbb2", "2026-11-10"), Kind.NOTIFICATION, "task-bbbb2", "2026-11-10", "10:00", "t", 200),
            entry(Kind.MIDNIGHT, null, "2026-11-12", "00:01", 400),
        )
        val s = AlarmDiff.stats(armed)
        assertEquals(2, s.armedCount)
        assertEquals("2026-11-08", s.armedThrough) // the last armed task entry by time (trigger 300)
        assertEquals(200L, s.nextAlarmMs)
        val none = AlarmDiff.stats(listOf(entry(Kind.MIDNIGHT, null, "2026-11-12", "00:01", 400)))
        assertEquals(0, none.armedCount)
        assertNull(none.armedThrough)
        assertNull(none.nextAlarmMs)
    }

    // ── the persisted store ─────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun storeRoundTripsEveryField() {
        val store = AlarmStore(File(tmp.root, "alarm_store.json"))
        assertEquals(StoreState(), store.read())
        val state = StoreState(
            entries = listOf(alarm("task-aaaa1", now + 5), entry(Kind.SNOOZE, "task-bbbb2", "2026-11-06", "12:10", now + 9, orig = Kind.ALARM)),
            feedEtag = "W/\"1.2026-11-06.14\"",
            feedAsOfMs = 123L,
            coveredUntil = "2026-11-19",
            settings = FeedSettings(dailyReminderOn = true, dailyReminderHour = 8, endOfDayOn = true, carryOverAlerts = false),
            serverTimezone = "Europe/London",
            lastPatchedTimezone = "Europe/London",
            armedThrough = "2026-11-10",
            armedCount = 7,
            nextAlarmMs = 99L,
            lastSyncMs = 55L,
            lastError = "boom",
            lastErrorCode = "server",
            exactAlarmAllowed = false,
            upgradeRequiredVersion = "2.0.0",
        )
        store.update { state }
        assertEquals(state, store.read())
        store.update { it.copy(armedCount = 8) }
        assertEquals(8, store.read().armedCount)
        assertEquals(state.entries, store.read().entries)
        store.clear()
        assertEquals(StoreState(), store.read())
    }

    @Test
    fun corruptStoreFileReadsAsEmptyInsteadOfCrashing() {
        val f = File(tmp.root, "alarm_store.json")
        f.writeText("{ this is not json")
        assertEquals(StoreState(), AlarmStore(f).read())
        assertFalse(AlarmStore(f).update { it.copy(armedCount = 1) }.entries.isNotEmpty())
        assertEquals(1, AlarmStore(f).read().armedCount)
    }

    // ── an entry past its nominal time that has not fired ───────────────────────────────────────────────────────

    @Test
    fun doesNotCancelAnEntryThatIsPastItsTimeButStillPlanned() {
        val late = alarm("task-late-1", now - 60_000)
        val plan = AlarmDiff.compute(listOf(late), listOf(late.copy()), now, isArmed = armedEverything)
        assertTrue("the OS registration must survive until the alarm is delivered", plan.toCancel.isEmpty())
        assertTrue(plan.toArm.isEmpty())
    }

    @Test
    fun cancelsAPastEntryThatLeftThePlan() {
        val late = alarm("task-late-1", now - 60_000)
        val plan = AlarmDiff.compute(listOf(late), emptyList(), now, isArmed = armedEverything)
        assertEquals(listOf(late.key), plan.toCancel)
    }

    @Test
    fun cancelsAPastEntryOnceTheGraceHasEnded() {
        val old = alarm("task-old-1", now - FeedPlanner.PENDING_GRACE_MS - 1_000)
        val plan = AlarmDiff.compute(listOf(old), listOf(old.copy()), now, isArmed = armedEverything)
        assertEquals(listOf(old.key), plan.toCancel)
    }
}
