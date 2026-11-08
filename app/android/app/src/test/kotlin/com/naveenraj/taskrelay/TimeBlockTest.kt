package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.TimeBlock.Span
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** The golden cases of web/test/timeblock.test.ts ("the one rule"); the Dart app uses the same ones. */
class TimeBlockTest {
    private fun block(start: String?, end: String?, duration: Int = 30) = TimeBlock.of(start, end, duration)

    // ── the golden cases (identical to the TypeScript test) ─────────────────────────────────────────────────────

    @Test
    fun startAndEndGiveTheBlock_startAloneLastsTheDuration_anEndAloneOrNothingIsNoBlock() {
        assertEquals(Span(540, 630), block("09:00", "10:30", 90))
        assertEquals(Span(540, 585), block("09:00", null, 45))
        assertNull(block(null, "17:00"))
        assertNull(block(null, null))
    }

    @Test
    fun aBlockThatWouldRunPastMidnightIsCutAtMidnight() {
        assertEquals(Span(1410, 1440), block("23:30", null, 120))
        assertEquals(Span(0, 1439), block("00:00", "23:59"))
    }

    @Test
    fun aBlockWithNoLengthIsNotABlock() {
        assertEquals(Span(1439, 1440), block("23:59", null, 30)) // the last minute of the day is still a minute
        assertNull(block("10:00", "10:00"))
        assertEquals(425, TimeBlock.toMinutes("07:05"))
    }

    // ── more edges of the same rule ─────────────────────────────────────────────────────────────────────────────

    @Test
    fun zeroOrNegativeLengthIsNoBlock() {
        assertNull(block("10:00", null, 0))
        assertNull(block("10:00", null, -15))
        assertNull(block("10:00", "09:59")) // an end before the start
    }

    @Test
    fun aHugeDurationIsCutAtMidnightWithoutOverflowing() {
        assertEquals(Span(600, 1440), block("10:00", null, Int.MAX_VALUE))
    }

    @Test
    fun anEmptyEndCountsAsNoEnd_aMalformedEndOrStartIsNoBlock() {
        assertEquals(Span(540, 570), block("09:00", "", 30)) // like the TypeScript `t.end_time ? ... : ...`
        assertNull(block("09:00", "9:30")) // fails open: a time that is not exactly HH:mm is no block
        assertNull(block("25:00", null))
        assertNull(block("09:60", null))
        assertNull(block("", null))
    }

    @Test
    fun spanIncludesItsStartAndExcludesItsEnd() {
        val s = Span(840, 930)
        assertFalse(839 in s)
        assertTrue(840 in s)
        assertTrue(929 in s)
        assertFalse(930 in s)
    }

    @Test
    fun toMinutesIsStrict() {
        assertEquals(0, TimeBlock.toMinutes("00:00"))
        assertEquals(1439, TimeBlock.toMinutes("23:59"))
        for (bad in listOf("24:00", "7:05", "07:5", "07-05", "07:05:00", " 07:05", "", "ab:cd")) assertNull(bad, TimeBlock.toMinutes(bad))
        assertNull(TimeBlock.toMinutes(null))
    }
}
