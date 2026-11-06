package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.ReplayAction.ACK
import com.naveenraj.taskrelay.ReplayAction.KEEP_RETRY
import com.naveenraj.taskrelay.ReplayAction.KEEP_RETRY_LATER
import com.naveenraj.taskrelay.ReplayAction.RETRY_WITHOUT_TIME
import com.naveenraj.taskrelay.ReplayAction.STOP_ALL
import com.naveenraj.taskrelay.ReplayAction.STOP_KEEP
import org.junit.Assert.assertEquals
import org.junit.Test

class ReplayPolicyTest {
    private fun d(status: Int, code: String? = null, io: Boolean = false, timeSent: Boolean = true) =
        ReplayPolicy.decide(status, code, io, timeSent)

    @Test
    fun success_isAcked() {
        for (s in listOf(200, 201, 204, 299)) assertEquals("status $s", ACK, d(s))
    }

    @Test
    fun notFoundAndUnprocessable_areAckedAsDropped() {
        assertEquals(ACK, d(404))
        assertEquals(ACK, d(404, "not_found"))
        assertEquals(ACK, d(422))
        assertEquals(ACK, d(422, "task_not_on_day"))
    }

    @Test
    fun invalidTime_retriesWithoutTime_once() {
        assertEquals(RETRY_WITHOUT_TIME, d(400, "invalid_time"))
        // already retried without completed_at: nothing more to strip, the record is dropped instead of looping
        assertEquals(ACK, d(400, "invalid_time", timeSent = false))
    }

    @Test
    fun otherBadRequests_areDropped() {
        assertEquals(ACK, d(400))
        assertEquals(ACK, d(400, "bad_request"))
        assertEquals(ACK, d(403, "forbidden"))
        assertEquals(ACK, d(409, "conflict"))
        assertEquals(ACK, d(410))
    }

    @Test
    fun unauthorized_stopsAndKeeps() {
        assertEquals(STOP_KEEP, d(401))
        assertEquals(STOP_KEEP, d(401, "unauthorized"))
    }

    @Test
    fun upgradeRequired_stopsAll() {
        assertEquals(STOP_ALL, d(426))
        assertEquals(STOP_ALL, d(426, "upgrade_required"))
    }

    @Test
    fun rateLimited_keepsAndRetriesLater() {
        assertEquals(KEEP_RETRY_LATER, d(429))
        assertEquals(KEEP_RETRY_LATER, d(429, "rate_limited"))
    }

    @Test
    fun serverErrorsAndIoErrors_keepAndRetry() {
        for (s in listOf(500, 502, 503, 504, 599)) assertEquals("status $s", KEEP_RETRY, d(s))
        assertEquals(KEEP_RETRY, d(0, io = true))
        assertEquals(KEEP_RETRY, d(404, io = true)) // an I/O error wins over whatever status was left over
        assertEquals(KEEP_RETRY, d(408))
    }

    @Test
    fun unexpectedStatuses_areKept() {
        assertEquals(KEEP_RETRY, d(301))
        assertEquals(KEEP_RETRY, d(302))
        assertEquals(KEEP_RETRY, d(100))
        assertEquals(KEEP_RETRY, d(0))
    }
}
