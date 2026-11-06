package com.naveenraj.taskrelay

import android.content.Context
import android.content.Intent
import android.text.SpannableString
import android.text.Spanned
import android.text.style.StrikethroughSpan
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import java.time.LocalDate
import java.time.ZoneId

/** Feeds the widget's ListView from [TodayCache]. */
class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    private class Factory(private val ctx: Context) : RemoteViewsFactory {
        private var rows: List<TodayTask> = emptyList()
        private var date: String = ""

        override fun onCreate() = Unit

        override fun onDataSetChanged() {
            val state = TodayWidgetProvider.currentState(ctx)
            rows = state.rows // empty when signed out, stale or nothing planned: the empty view shows the right message
            date = LocalDate.now(ZoneId.systemDefault()).toString()
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews {
            val rv = RemoteViews(ctx.packageName, R.layout.widget_row)
            val t = rows.getOrNull(position) ?: return rv
            val title = t.title.ifBlank { "(untitled)" }
            val text = SpannableString(title)
            if (t.done) text.setSpan(StrikethroughSpan(), 0, text.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            val color = ctx.getColor(if (t.done) R.color.widget_muted else R.color.widget_fg)
            rv.setTextViewText(R.id.row_check, if (t.done) "☑" else "☐")
            rv.setTextViewText(R.id.row_title, text)
            rv.setTextColor(R.id.row_check, color)
            rv.setTextColor(R.id.row_title, color)
            rv.setContentDescription(R.id.row_root, if (t.done) "$title, done" else "$title, not done. Tap to complete")
            // Merged into the list's template: a tap becomes a WidgetActionReceiver broadcast for this task + date.
            rv.setOnClickFillInIntent(
                R.id.row_root,
                Intent()
                    .putExtra(Extras.TASK_ID, t.id)
                    .putExtra(Extras.DATE, date)
                    .putExtra(WidgetActionReceiver.EXTRA_DONE, t.done),
            )
            return rv
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 1

        override fun getItemId(position: Int): Long = rows.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

        override fun hasStableIds(): Boolean = true
    }
}
