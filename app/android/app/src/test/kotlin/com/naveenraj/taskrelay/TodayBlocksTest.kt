package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.TimeBlock.Span
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant
import java.time.ZoneOffset

/** `today.blocks`: parsed from the REAL contract fixture, kept in the cache, flipped by a Complete. */
class TodayBlocksTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun fixtureToday() = FeedParser.parse(TestFixtures.syncJson()).today

    private fun blk(id: String, start: String = "10:00", end: String? = null, done: Boolean = false) = TodayBlock(id, "T $id", start, end, 30, done)

    // ── the feed ────────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun parsesTheBlocksOfTheRealFixture() {
        val blocks = fixtureToday().blocks
        assertEquals(listOf("fx-task-standup", "fx-task-report", "fx-task-gym"), blocks.map { it.id }) // earliest first, as sent
        assertEquals(FeedBlock("fx-task-standup", "Team standup", "09:30", "09:45", 15, done = true), blocks[0])
        assertEquals(FeedBlock("fx-task-report", "Write quarterly report", "14:00", null, 90, done = false), blocks[1]) // "end_time": null
        assertEquals(FeedBlock("fx-task-gym", "Gym", "18:00", "19:00", 60, done = false), blocks[2])
    }

    @Test
    fun theFixturesExistingFieldsAreUnchanged() {
        val t = fixtureToday()
        assertEquals(4, t.planned)
        assertEquals(1, t.done)
        assertEquals(1, t.overdueCount)
        assertEquals(listOf("Team standup", "Gym"), t.top)
        assertEquals(4, t.tasks.size)
    }

    @Test
    fun anOlderServerSendsNoBlocks() {
        val root = JSONObject(TestFixtures.syncJson())
        root.getJSONObject("today").remove("blocks")
        assertTrue(FeedParser.parse(root.toString()).today.blocks.isEmpty())
        root.remove("today")
        assertTrue(FeedParser.parse(root.toString()).today.blocks.isEmpty())
    }

    @Test
    fun aBadBlockIsDroppedOrFailsOpenNeverCrashes() {
        val root = JSONObject(TestFixtures.syncJson())
        root.getJSONObject("today").put(
            "blocks",
            org.json.JSONArray(
                """[
                  {"title":"no id","start_time":"10:00","end_time":null,"duration_min":30,"status":"open"},
                  {"id":"no-start-0001","title":"no start","end_time":"11:00","duration_min":30,"status":"open"},
                  {"id":"bad-end-0001","title":"bad end","start_time":"10:00","end_time":"soon","duration_min":30,"status":"open"},
                  "junk",
                  {"id":"ok-block-0001","title":"fine","start_time":"12:00","end_time":"12:30","duration_min":30,"status":"open"}
                ]""",
            ),
        )
        val blocks = FeedParser.parse(root.toString()).today.blocks
        assertEquals(listOf("bad-end-0001", "ok-block-0001"), blocks.map { it.id })
        val cached = TodayData.fromFeed(FeedParser.parse(root.toString()).today, 1L).blocks
        assertNull(cached[0].span) // an end that is not HH:mm is no block: the blocker fails open
        assertEquals(Span(720, 750), cached[1].span)
    }

    @Test
    fun theCacheKeepsAtMost50Blocks() {
        val many = FeedToday("2026-11-06", 80, 0, 0, emptyList(), emptyList(), (0 until 80).map { FeedBlock("task-%05d".format(it), "T$it", "10:00", null, 5, false) })
        assertEquals(50, TodayData.fromFeed(many, 1L).blocks.size)
    }

    // ── the cache ───────────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun fromFeedCopiesTheBlocksAndTheirSpans() {
        val d = TodayData.fromFeed(fixtureToday(), 42L)
        assertEquals(3, d.blocks.size)
        assertEquals(listOf(Span(570, 585), Span(840, 930), Span(1080, 1140)), d.blocks.map { it.span })
        assertEquals(listOf(true, false, false), d.blocks.map { it.done })
    }

    @Test
    fun blocksSurviveTheCacheFile() {
        val cache = TodayCache(File(tmp.root, "today_cache.json"))
        val today = fixtureToday()
        cache.writeFeed(today, 42L) { emptyList() }
        assertEquals(TodayData.fromFeed(today, 42L), cache.read())
        assertNull(cache.read()!!.blocks[1].endTime) // a null end survives the JSON round trip as null, not "null"
        // a Complete rewrites the file: the flipped block is what the next reader sees
        cache.markDone("fx-task-gym", "2026-11-06")
        assertTrue(cache.read()!!.blocks.first { it.id == "fx-task-gym" }.done)
        assertTrue(cache.read()!!.tasks.first { it.id == "fx-task-gym" }.done)
    }

    @Test
    fun aCacheWrittenBeforeBlocksExistedStillLoads() {
        val old = """{"date":"2026-11-06","planned":4,"done":1,"overdue_count":1,"top":["Team standup","Gym"],
            "tasks":[{"id":"fx-task-gym","title":"Gym","done":false,"is_top":true,"duration_min":60}],
            "pending":["fx-task-gym|2026-11-06"],"updatedMs":42}"""
        File(tmp.root, "today_cache.json").writeText(old)
        val d = TodayCache(File(tmp.root, "today_cache.json")).read()!!
        assertTrue(d.blocks.isEmpty())
        assertEquals("2026-11-06", d.date)
        assertEquals(4, d.planned)
        assertEquals(1, d.done)
        assertEquals(listOf("fx-task-gym|2026-11-06"), d.pending)
        assertEquals(1, d.tasks.size)
        // and a Complete on it keeps working (and writes the new shape)
        TodayCache(File(tmp.root, "today_cache.json")).markDone("fx-task-gym", "2026-11-06")
        val after = TodayCache(File(tmp.root, "today_cache.json")).read()!!
        assertEquals(2, after.done)
        assertTrue(after.blocks.isEmpty())
    }

    // ── a Complete flips the block and keeps the counts right ───────────────────────────────────────────────────

    @Test
    fun completingFlipsTheMatchingBlockAndCountsOnce() {
        val t = TodayData.fromFeed(fixtureToday(), 1L).withCompleted("fx-task-gym", "2026-11-06")
        assertTrue(t.blocks.first { it.id == "fx-task-gym" }.done)
        assertTrue(t.tasks.first { it.id == "fx-task-gym" }.done)
        assertEquals(2, t.done)
        assertFalse(t.blocks.first { it.id == "fx-task-report" }.done) // the others are untouched
        assertTrue(t.blocks.first { it.id == "fx-task-standup" }.done)
        assertEquals(listOf("fx-task-gym|2026-11-06"), t.pending)
        assertEquals(t, t.withCompleted("fx-task-gym", "2026-11-06")) // idempotent
    }

    @Test
    fun theBlockerSeesTheCompleteStraightAway() {
        val now = Instant.parse("2026-11-06T18:30:00Z").toEpochMilli()
        val before = TodayData.fromFeed(fixtureToday(), 1L)
        val after = before.withCompleted("fx-task-gym", "2026-11-06") // done from a notification at 18:30
        // until_done: the count drops by one
        val untilDone = BlockerConfig(enabled = true, mode = BlockerConfig.MODE_UNTIL_DONE)
        assertEquals(3, BlockerPolicy.decide(untilDone, before, now, ZoneOffset.UTC).left)
        assertEquals(2, BlockerPolicy.decide(untilDone, after, now, ZoneOffset.UTC).left)
        // free_time: Gym's own block stops blocking
        val free = BlockerConfig(enabled = true, mode = BlockerConfig.MODE_FREE_TIME)
        assertEquals(BlockCode.TASK_BLOCK, BlockerPolicy.decide(free, before, now, ZoneOffset.UTC).code)
        assertEquals(BlockCode.FREE_TIME, BlockerPolicy.decide(free, after, now, ZoneOffset.UTC).code)
    }

    @Test
    fun completingATaskBeyondTheTaskCapStillFlipsItsBlock() {
        // 30 open tasks, only the first 25 are in `tasks`; the 29th has a block
        val tasks = (0 until 25).map { TodayTask("task-%05d".format(it), "T$it", false, false, 5) }
        val d = TodayData("2026-11-06", 30, 0, 0, emptyList(), tasks, blocks = listOf(blk("task-00028")))
        val t = d.withCompleted("task-00028", "2026-11-06")
        assertTrue(t.blocks.single().done)
        assertEquals(1, t.done) // counted once
        assertEquals(1, t.withCompleted("task-00028", "2026-11-06").done) // and not again
    }

    @Test
    fun aBlockThatIsAlreadyDoneMeansTheServerCountedItAlready() {
        // the task is beyond the task cap, its block says done: completing it again must not push `done` up
        val tasks = (0 until 25).map { TodayTask("task-%05d".format(it), "T$it", false, false, 5) }
        val d = TodayData("2026-11-06", 30, 5, 0, emptyList(), tasks, blocks = listOf(blk("task-00028", done = true)))
        val t = d.withCompleted("task-00028", "2026-11-06")
        assertEquals(5, t.done)
        assertTrue(t.blocks.single().done)
        assertEquals(listOf("task-00028|2026-11-06"), t.pending)
    }

    @Test
    fun completingAnotherDayOrAnUnknownTaskLeavesBlocksAlone() {
        val d = TodayData.fromFeed(fixtureToday(), 1L)
        val otherDay = d.withCompleted("fx-task-gym", "2026-11-07")
        assertEquals(d.blocks, otherDay.blocks)
        assertEquals(d.done, otherDay.done)
        val unknown = d.withCompleted("no-such-task-1", "2026-11-06")
        assertEquals(d.blocks, unknown.blocks)
    }

    @Test
    fun pendingCompletesFlipBlocksOnAFreshSnapshot() {
        val fresh = TodayData.fromFeed(fixtureToday(), 1L)
        val t = fresh.withPendingApplied(listOf(TaskDay("fx-task-gym", "2026-11-06"), TaskDay("fx-task-report", "2026-11-06")))
        assertTrue(t.blocks.all { it.done })
        assertEquals(3, t.done)
    }

    @Test
    fun theSpanOfABlockFollowsTheOneRule() {
        assertEquals(Span(570, 585), blk("a", "09:30", "09:45").span)
        assertEquals(Span(600, 630), blk("a", "10:00", null).span) // 30 min estimate
        assertNull(TodayBlock("a", "t", "10:00", null, 0, false).span)
        assertNull(TodayBlock("a", "t", "10:00", "10:00", 30, false).span)
    }
}
