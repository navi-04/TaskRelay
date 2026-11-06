package com.naveenraj.taskrelay

/** What to do with one replayed action-log record after the server answered. */
enum class ReplayAction {
    /** Done (2xx), or permanently rejected / obsolete (404, 422, other 4xx): remove the record from the log. */
    ACK,

    /** 400 `invalid_time`: the tap time was rejected (phone clock ahead of the server); retry once without `completed_at`. */
    RETRY_WITHOUT_TIME,

    /** 401: the session expired. Stop replaying, keep every record, flag the session. */
    STOP_KEEP,

    /** 426: this app version is too old. Stop all sync (records are kept). */
    STOP_ALL,

    /** 429: keep the record, stop for now and try again after Retry-After. */
    KEEP_RETRY_LATER,

    /** 5xx, timeouts and I/O errors: keep the record and retry on the next sync. */
    KEEP_RETRY,
}

/** PURE decision table for the action-log replay. */
object ReplayPolicy {
    /**
     * @param status HTTP status, or 0 / ignored when [ioError] is true.
     * @param errorCode `error.code` from the JSON body, if any.
     * @param ioError a connection / timeout / TLS failure (no HTTP response).
     * @param timeSent whether the request carried `completed_at` (the `invalid_time` retry only makes sense then).
     */
    fun decide(status: Int, errorCode: String?, ioError: Boolean = false, timeSent: Boolean = true): ReplayAction {
        if (ioError) return ReplayAction.KEEP_RETRY
        return when {
            status in 200..299 -> ReplayAction.ACK
            status == 401 -> ReplayAction.STOP_KEEP
            status == 426 -> ReplayAction.STOP_ALL
            status == 429 -> ReplayAction.KEEP_RETRY_LATER
            status == 404 || status == 422 -> ReplayAction.ACK // task deleted / no longer occurs on that day
            status == 400 && errorCode == "invalid_time" && timeSent -> ReplayAction.RETRY_WITHOUT_TIME
            status == 408 -> ReplayAction.KEEP_RETRY
            // Any other 4xx (validation error, forbidden, conflict, gone ...) will never succeed on replay: drop it so one
            // poisoned record cannot block the log forever.
            status in 400..499 -> ReplayAction.ACK
            else -> ReplayAction.KEEP_RETRY // 5xx and anything unexpected (3xx, 1xx)
        }
    }
}
