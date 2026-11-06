package com.naveenraj.taskrelay

/** PURE: the text of the daily / end-of-day reminders, composed AT FIRE TIME from the freshest TodayCache. */
object ReminderText {
    data class Text(val title: String, val body: String)

    private const val SEP = " · " // " · "

    /** "<planned> tasks today · Top 3: a, b, c · <n> overdue". [todayDate] is the device's current yyyy-MM-dd. */
    fun daily(today: TodayData?, todayDate: String, carryOverAlerts: Boolean): Text {
        val title = "Good morning"
        if (today == null || today.date != todayDate) return Text(title, "Open TaskRelay to see today's plan")
        if (today.planned <= 0) return Text(title, "Nothing planned today")
        val parts = ArrayList<String>(3)
        parts.add(if (today.planned == 1) "1 task today" else "${today.planned} tasks today")
        val top = today.top.filter { it.isNotBlank() }.take(3)
        if (top.isNotEmpty()) parts.add("Top 3: " + top.joinToString(", "))
        if (carryOverAlerts && today.overdueCount > 0) parts.add("${today.overdueCount} overdue")
        return Text(title, parts.joinToString(SEP))
    }

    /** "Today: <done> of <planned> done" + "Nice work!" when everything is done, "<n> left" otherwise. */
    fun endOfDay(today: TodayData?, todayDate: String): Text {
        val title = "End of day"
        if (today == null || today.date != todayDate) return Text(title, "Open TaskRelay to review today")
        if (today.planned <= 0) return Text(title, "Nothing was planned today")
        val base = "Today: ${today.done} of ${today.planned} done"
        val tail = if (today.done >= today.planned) "Nice work!" else "${today.planned - today.done} left"
        return Text(title, base + SEP + tail)
    }
}
