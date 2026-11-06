package com.naveenraj.taskrelay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ActionLogTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private fun log(): ActionLog = ActionLog(File(tmp.root, "alarm_actions.log"))

    @Test
    fun emptyLog() {
        val l = log()
        assertEquals(emptyList<String>(), l.peek())
        assertEquals(0, l.count())
        l.ack(listOf("anything")) // no file: no-op
    }

    @Test
    fun appendsAreReadBackInOrder() {
        val l = log()
        assertTrue(l.appendComplete("task-aaaa1", "2026-11-06", 1000))
        assertTrue(l.appendComplete("task-bbbb2", "2026-11-07", 2000))
        assertTrue(l.appendComplete("task-aaaa1", "2026-11-08", 3000))
        assertEquals(
            listOf(
                "task-aaaa1|2026-11-06|complete|1000",
                "task-bbbb2|2026-11-07|complete|2000",
                "task-aaaa1|2026-11-08|complete|3000",
            ),
            l.peek(),
        )
        assertEquals(3, l.count())
    }

    @Test
    fun lineFormatIsTaskDateCompleteTimestamp_andPipeFree() {
        val l = log()
        l.appendComplete("fx-task-gym", "2026-11-06", 1762430400123)
        val line = l.peek().single()
        assertEquals("fx-task-gym|2026-11-06|complete|1762430400123", line)
        assertEquals(4, line.split('|').size)
        val rec = ActionLog.parse(line)
        assertNotNull(rec)
        assertEquals("fx-task-gym", rec!!.taskId)
        assertEquals("2026-11-06", rec.date)
        assertEquals("complete", rec.type)
        assertEquals(1762430400123, rec.tapMs)
    }

    @Test
    fun malformedIdsAreRejectedAndNothingIsWritten() {
        val l = log()
        assertFalse(l.appendComplete("a|b-1234567", "2026-11-06", 1)) // '|' inside the id
        assertFalse(l.appendComplete("short", "2026-11-06", 1)) // < 8 chars
        assertFalse(l.appendComplete("x".repeat(65), "2026-11-06", 1)) // > 64 chars
        assertFalse(l.appendComplete("task id 12", "2026-11-06", 1)) // space
        assertFalse(l.appendComplete("task-aaaa1", "2026/11/06", 1)) // bad date
        assertFalse(l.appendComplete("task-aaaa1", "2026-11-06", 0)) // no timestamp
        assertEquals(0, l.count())
    }

    @Test(expected = IllegalArgumentException::class)
    fun rawAppendRejectsLineBreaks() {
        log().append("a\nb")
    }

    @Test
    fun parseRejectsGarbage() {
        assertNull(ActionLog.parse("garbage"))
        assertNull(ActionLog.parse("task-aaaa1|2026-11-06|open|1"))
        assertNull(ActionLog.parse("task-aaaa1|2026-11-06|complete|notanumber"))
        assertNull(ActionLog.parse("task-aaaa1|2026-11-06|complete|1|extra"))
        assertNull(ActionLog.parse("short|2026-11-06|complete|1"))
    }

    @Test
    fun ackRemovesExactlyTheGivenLines() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        l.appendComplete("task-bbbb2", "2026-11-06", 2)
        l.appendComplete("task-cccc3", "2026-11-06", 3)
        val peeked = l.peek()
        l.ack(listOf(peeked[0], peeked[2]))
        assertEquals(listOf(peeked[1]), l.peek())
        l.ack(listOf(peeked[1]))
        assertEquals(emptyList<String>(), l.peek())
    }

    @Test
    fun ackKeepsLinesAppendedAfterThePeek() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        val drained = l.peek()
        l.appendComplete("task-bbbb2", "2026-11-06", 2) // tapped while the sync was running
        l.ack(drained)
        assertEquals(listOf("task-bbbb2|2026-11-06|complete|2"), l.peek())
    }

    @Test
    fun ackOfLinesNotPresentIsANoOp() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        l.ack(listOf("task-zzzz9|2026-11-06|complete|9", "not even a record"))
        assertEquals(listOf("task-aaaa1|2026-11-06|complete|1"), l.peek())
        l.ack(emptyList())
        assertEquals(1, l.count())
    }

    @Test
    fun ackTwiceIsSafe() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        l.appendComplete("task-bbbb2", "2026-11-06", 2)
        val drained = l.peek()
        l.ack(drained)
        l.ack(drained) // the second, overlapping drain finishes later: nothing left to remove, nothing broken
        assertEquals(0, l.count())
    }

    @Test
    fun duplicateLinesAreRemovedOnePerAck() {
        val l = log()
        l.append("task-aaaa1|2026-11-06|complete|5")
        l.append("task-aaaa1|2026-11-06|complete|5")
        l.ack(listOf("task-aaaa1|2026-11-06|complete|5"))
        assertEquals(1, l.count())
        l.ack(listOf("task-aaaa1|2026-11-06|complete|5"))
        assertEquals(0, l.count())
    }

    @Test
    fun overlappingDrainsAckingTheSameLinesConcurrentlyAreSafe() {
        val l = log()
        val total = 200
        for (i in 0 until total) l.appendComplete("task-%05d".format(i), "2026-11-06", (i + 1).toLong())
        val drainA = l.peek()
        val drainB = l.peek()
        val keep = ActionLog(File(tmp.root, "alarm_actions.log")) // another instance on the same file shares the process-wide lock

        val pool = Executors.newFixedThreadPool(3)
        val go = CountDownLatch(1)
        val extra = Runnable { go.await(); for (i in 0 until 20) keep.appendComplete("late-%05d".format(i), "2026-11-07", (1000 + i).toLong()) }
        val a = Runnable { go.await(); drainA.chunked(7).forEach { l.ack(it) } }
        val b = Runnable { go.await(); drainB.chunked(11).forEach { l.ack(it) } }
        val futures = listOf(pool.submit(a), pool.submit(b), pool.submit(extra))
        go.countDown()
        futures.forEach { it.get(30, TimeUnit.SECONDS) }
        pool.shutdown()

        val left = l.peek()
        assertEquals(20, left.size) // exactly the lines nobody acked
        assertTrue(left.all { it.startsWith("late-") })
        assertEquals(20, left.toSet().size)
    }

    @Test
    fun concurrentAppendsAreAllDurableAndIntact() {
        val l = log()
        val threads = 8
        val per = 50
        val pool = Executors.newFixedThreadPool(threads)
        val go = CountDownLatch(1)
        val futures = (0 until threads).map { t ->
            pool.submit {
                go.await()
                for (i in 0 until per) l.appendComplete("task-t%02d-%03d".format(t, i), "2026-11-06", (t * 1000 + i + 1).toLong())
            }
        }
        go.countDown()
        futures.forEach { it.get(30, TimeUnit.SECONDS) }
        pool.shutdown()
        val lines = l.peek()
        assertEquals(threads * per, lines.size)
        assertEquals(threads * per, lines.toSet().size)
        assertTrue(lines.all { ActionLog.parse(it) != null }) // no interleaved / torn lines
    }

    @Test
    fun tornLastLineDoesNotCorruptTheNextAppend() {
        val f = File(tmp.root, "alarm_actions.log")
        f.writeText("task-aaaa1|2026-11-06|complete|1\ntask-bbbb2|2026-1") // process died mid-write
        val l = ActionLog(f)
        l.appendComplete("task-cccc3", "2026-11-06", 3)
        val lines = l.peek()
        assertEquals(3, lines.size)
        assertEquals("task-cccc3|2026-11-06|complete|3", lines.last())
        assertNull(ActionLog.parse(lines[1])) // the torn record is garbage the sync will drop, nothing else is harmed
        assertNotNull(ActionLog.parse(lines[2]))
    }

    @Test
    fun pendingCompletesAndClear() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        l.appendComplete("task-aaaa1", "2026-11-07", 2)
        l.append("garbage")
        assertEquals(setOf(TaskDay("task-aaaa1", "2026-11-06"), TaskDay("task-aaaa1", "2026-11-07")), l.pendingCompletes())
        assertTrue(l.hasComplete("task-aaaa1", "2026-11-07"))
        assertFalse(l.hasComplete("task-aaaa1", "2026-11-08"))
        l.clear()
        assertEquals(0, l.count())
    }

    @Test
    fun ackRewritesThroughAtomicReplaceAndLeavesNoTempFile() {
        val l = log()
        l.appendComplete("task-aaaa1", "2026-11-06", 1)
        l.appendComplete("task-bbbb2", "2026-11-06", 2)
        l.ack(listOf(l.peek()[0]))
        assertFalse(File(tmp.root, "alarm_actions.log.tmp").exists())
        assertEquals(1, l.count())
    }
}
