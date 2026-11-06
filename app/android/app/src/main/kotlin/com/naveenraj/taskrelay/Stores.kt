package com.naveenraj.taskrelay

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

/** Factories for the file-backed stores. Instances are cheap: the locks that matter are process-wide statics. */
object Stores {
    fun actionLog(ctx: Context) = ActionLog(File(ctx.applicationContext.filesDir, "alarm_actions.log"))
    fun alarmStore(ctx: Context) = AlarmStore(File(ctx.applicationContext.filesDir, "alarm_store.json"))
    fun todayCache(ctx: Context) = TodayCache(File(ctx.applicationContext.filesDir, "today_cache.json"))
}

/** Shared background executor (file I/O, keystore, HTTP) and the main-thread handler. */
object Bg {
    val io: ExecutorService = Executors.newFixedThreadPool(3, object : java.util.concurrent.ThreadFactory {
        private val n = AtomicInteger(0)
        override fun newThread(r: Runnable): Thread =
            Thread(r, "taskrelay-bg-${n.incrementAndGet()}").apply { isDaemon = true }
    })

    val main: Handler = Handler(Looper.getMainLooper())
}
