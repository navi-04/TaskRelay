package com.naveenraj.taskrelay

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.util.concurrent.TimeUnit

/**
 * Background sync. Periodic (45 min, flex 15 min, network required) keeps the alarm horizon topped up; one-time runs follow user
 * actions, the midnight trigger and reboots.
 *
 * Known limit: Doze / App Standby can stretch the periodic run to hours. Alarms that are already armed with AlarmManager still ring.
 */
class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        val trigger = inputData.getString(KEY_TRIGGER) ?: "periodic"
        val r = SyncClient(applicationContext).runOnce(trigger)
        return when {
            // 429: honour Retry-After with a separate delayed one-time run instead of WorkManager's own backoff.
            r.errorCode == "rate_limited" -> {
                enqueueRetry(applicationContext, (r.retryAfterSec ?: 60L).coerceIn(30L, 3600L))
                Result.success()
            }
            r.retryable && runAttemptCount < MAX_ATTEMPTS -> Result.retry()
            // unauthorized / upgrade_required / not_signed_in / permanent 4xx: nothing to retry; the next periodic run tries again
            else -> Result.success()
        }
    }

    companion object {
        private const val TAG = "SyncWorker"
        const val UNIQUE_PERIODIC = "sync-periodic"
        const val UNIQUE_ONCE = "sync-once"
        const val UNIQUE_RETRY = "sync-retry"
        private const val KEY_TRIGGER = "trigger"
        private const val MAX_ATTEMPTS = 6

        private val NETWORK = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

        /** Periodic sync, KEEP: calling it repeatedly never resets the schedule. */
        fun schedulePeriodic(ctx: Context) = safely("schedulePeriodic") {
            val req = PeriodicWorkRequestBuilder<SyncWorker>(45, TimeUnit.MINUTES, 15, TimeUnit.MINUTES)
                .setConstraints(NETWORK)
                .setInputData(workDataOf(KEY_TRIGGER to "periodic"))
                .build()
            WorkManager.getInstance(ctx.applicationContext)
                .enqueueUniquePeriodicWork(UNIQUE_PERIODIC, ExistingPeriodicWorkPolicy.KEEP, req)
        }

        /**
         * One-time sync as soon as there is a network. REPLACE with a short initial delay so a burst of taps (each of which calls
         * this) coalesces into one run. Exponential backoff starts at 30 s.
         */
        fun enqueueOnce(ctx: Context, delaySec: Long = 2) = safely("enqueueOnce") {
            val req = OneTimeWorkRequestBuilder<SyncWorker>()
                .setInitialDelay(delaySec, TimeUnit.SECONDS)
                .setConstraints(NETWORK)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .setInputData(workDataOf(KEY_TRIGGER to "once"))
                .build()
            WorkManager.getInstance(ctx.applicationContext).enqueueUniqueWork(UNIQUE_ONCE, ExistingWorkPolicy.REPLACE, req)
        }

        private fun enqueueRetry(ctx: Context, delaySec: Long) = safely("enqueueRetry") {
            val req = OneTimeWorkRequestBuilder<SyncWorker>()
                .setInitialDelay(delaySec, TimeUnit.SECONDS)
                .setConstraints(NETWORK)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .setInputData(workDataOf(KEY_TRIGGER to "retry"))
                .build()
            WorkManager.getInstance(ctx.applicationContext).enqueueUniqueWork(UNIQUE_RETRY, ExistingWorkPolicy.REPLACE, req)
        }

        /** Sign-out: no periodic, one-time or retry work may survive. */
        fun cancelAll(ctx: Context) = safely("cancelAll") {
            val wm = WorkManager.getInstance(ctx.applicationContext)
            wm.cancelUniqueWork(UNIQUE_PERIODIC)
            wm.cancelUniqueWork(UNIQUE_ONCE)
            wm.cancelUniqueWork(UNIQUE_RETRY)
        }

        private inline fun safely(what: String, block: () -> Unit) {
            try {
                block()
            } catch (t: Throwable) {
                Log.e(TAG, "$what failed: ${t.javaClass.simpleName}")
            }
        }
    }
}
