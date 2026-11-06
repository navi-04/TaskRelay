package com.naveenraj.taskrelay

/** PURE: what the home-screen widget shows, derived from the session + the TodayCache + today's date. */
data class WidgetState(
    val mode: Mode,
    /** "<done>/<planned>" or "" when there is nothing to count. */
    val count: String,
    /** Shown instead of the list when there are no rows. */
    val emptyText: String,
    val rows: List<TodayTask>,
) {
    enum class Mode { SIGNED_OUT, STALE, EMPTY, OK }

    companion object {
        const val SIGNED_OUT_TEXT = "Sign in to TaskRelay"
        const val STALE_TEXT = "Open TaskRelay to refresh"
        const val EMPTY_TEXT = "Nothing planned today"

        fun compute(signedIn: Boolean, cache: TodayData?, todayDate: String): WidgetState = when {
            !signedIn -> WidgetState(Mode.SIGNED_OUT, "", SIGNED_OUT_TEXT, emptyList())
            cache == null || cache.date != todayDate -> WidgetState(Mode.STALE, "", STALE_TEXT, emptyList())
            cache.tasks.isEmpty() -> WidgetState(Mode.EMPTY, "${cache.done}/${cache.planned}", EMPTY_TEXT, emptyList())
            else -> WidgetState(Mode.OK, "${cache.done}/${cache.planned}", "", cache.tasks)
        }
    }
}
