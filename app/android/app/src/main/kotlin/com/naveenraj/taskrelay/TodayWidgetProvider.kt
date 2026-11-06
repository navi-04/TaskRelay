package com.naveenraj.taskrelay

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZoneId

/**
 * Home-screen widget (pure native, no extra libraries): header "Today", "<done>/<planned>" and a "+" button, a list of today's
 * tasks (checkbox glyph + one-line title) and an empty view. Data comes from [TodayCache]; it refreshes after every sync, at the
 * `midnight` entry and on timezone change (updatePeriodMillis is 0: nothing wakes the device just for the widget).
 */
class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, buildViews(context, id))
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, R.id.widget_list)
    }

    override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle?) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        appWidgetManager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId))
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        SyncWorker.enqueueOnce(context) // first widget placed: fetch today's data
    }

    companion object {
        private const val TAG = "TodayWidget"
        private const val REQ_ADD = 21
        private const val REQ_HEADER = 22
        private const val REQ_ROW = 23

        /** Re-renders every placed widget and reloads its list. Safe to call from any thread, a no-op without widgets. */
        fun refreshAll(ctx: Context) {
            try {
                val app = ctx.applicationContext
                val mgr = AppWidgetManager.getInstance(app)
                val ids = mgr.getAppWidgetIds(ComponentName(app, TodayWidgetProvider::class.java))
                if (ids.isEmpty()) return
                for (id in ids) mgr.updateAppWidget(id, buildViews(app, id))
                mgr.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
            } catch (t: Throwable) {
                Log.w(TAG, "refresh failed: ${t.javaClass.simpleName}")
            }
        }

        /** The widget's current state from the session, the cache and today's date in the device zone. */
        fun currentState(ctx: Context): WidgetState =
            WidgetState.compute(
                signedIn = SessionStore.isSignedIn(ctx),
                cache = Stores.todayCache(ctx).read(),
                todayDate = LocalDate.now(ZoneId.systemDefault()).toString(),
            )

        private fun buildViews(ctx: Context, widgetId: Int): RemoteViews {
            val state = currentState(ctx)
            val rv = RemoteViews(ctx.packageName, R.layout.widget_today)
            rv.setTextViewText(R.id.widget_title, "Today")
            rv.setTextViewText(R.id.widget_count, state.count)
            rv.setTextViewText(R.id.widget_empty, state.emptyText)

            val adapter = Intent(ctx, TodayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME)) // makes the intent unique per widget id
            }
            rv.setRemoteAdapter(R.id.widget_list, adapter)
            rv.setEmptyView(R.id.widget_list, R.id.widget_empty)

            // A row tap is a broadcast built from this template + the row's fill-in intent (hence mutable on API 31+).
            val template = Intent(ctx, WidgetActionReceiver::class.java).setAction(WidgetActionReceiver.ACTION_ROW_TAP)
            val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            rv.setPendingIntentTemplate(
                R.id.widget_list,
                PendingIntent.getBroadcast(ctx, REQ_ROW, template, PendingIntent.FLAG_UPDATE_CURRENT or mutable),
            )

            val immutableUpdate = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            // "+" opens the app on the add form (Dart reads it with getLaunchAction)
            val add = Notifications.openAppIntent(ctx, "add").putExtra(LaunchState.EXTRA_OPEN_ADD, true)
            rv.setOnClickPendingIntent(R.id.widget_add, PendingIntent.getActivity(ctx, REQ_ADD, add, immutableUpdate))
            val open = PendingIntent.getActivity(ctx, REQ_HEADER, Notifications.openAppIntent(ctx, "widget"), immutableUpdate)
            rv.setOnClickPendingIntent(R.id.widget_header, open)
            rv.setOnClickPendingIntent(R.id.widget_empty, open)
            return rv
        }
    }
}
