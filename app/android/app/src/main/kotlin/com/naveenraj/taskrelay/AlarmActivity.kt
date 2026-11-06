package com.naveenraj.taskrelay

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/**
 * The full-screen alarm over the lock screen (launched by the alarm notification's full-screen intent).
 *
 * Complete / Snooze 10 min / Dismiss all go through [AlarmActions]. The Back button (and the predictive back gesture on
 * Android 13-16) is swallowed through an OnBackPressedDispatcher callback: a ringing alarm must be answered explicitly.
 * No KeyguardLock, no bright wake lock: setShowWhenLocked / setTurnScreenOn plus FLAG_KEEP_SCREEN_ON are enough.
 */
class AlarmActivity : ComponentActivity() {

    private var entry: Entry? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val e = Entry.fromIntent(intent)
        if (e == null) {
            finish()
            return
        }
        entry = e
        instance = this

        showOverLockScreen()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // Intentionally empty: Complete, Snooze or Dismiss must be chosen.
            }
        })

        setContentView(R.layout.activity_alarm)
        bind(e)
        findViewById<Button>(R.id.completeButton).setOnClickListener { onComplete() }
        findViewById<Button>(R.id.snoozeButton).setOnClickListener { onSnooze() }
        findViewById<Button>(R.id.dismissButton).setOnClickListener { onDismiss() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Entry.fromIntent(intent)?.let { updateFrom(it) }
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Called by AlarmService when another alarm replaces the one on screen. */
    fun updateFrom(e: Entry) {
        entry = e
        runOnUiThread { bind(e) }
    }

    private fun bind(e: Entry) {
        findViewById<TextView>(R.id.alarmTitle)?.text = e.title
        findViewById<TextView>(R.id.alarmTime)?.text = LocalTime.now().format(TIME_FORMAT)
        val canAct = e.taskId != null
        findViewById<Button>(R.id.completeButton)?.isEnabled = canAct
        findViewById<Button>(R.id.snoozeButton)?.isEnabled = canAct
    }

    @Suppress("DEPRECATION")
    private fun showOverLockScreen() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON,
            )
        }
    }

    // File and keystore I/O stays off the main thread; the process is alive (foreground service / visible activity) while it runs.
    private fun onComplete() {
        val e = entry ?: return
        val id = e.taskId
        val app = applicationContext
        val tapMs = System.currentTimeMillis() // the tap time, not the time the background thread gets to it
        Bg.io.execute { if (id != null) AlarmActions.complete(app, e.key, id, e.date, tapMs) else AlarmActions.dismiss(app, e.key) }
        finish()
    }

    private fun onSnooze() {
        val e = entry ?: return
        val app = applicationContext
        val tapMs = System.currentTimeMillis()
        Bg.io.execute { AlarmActions.snooze(app, e, tapMs) }
        finish()
    }

    private fun onDismiss() {
        AlarmActions.dismiss(this, entry?.key)
        finish()
    }

    companion object {
        private val TIME_FORMAT: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

        /** The visible instance, so AlarmService can update or close it. Main thread only. */
        @Volatile
        var instance: AlarmActivity? = null

        fun finishIfShowing() {
            val a = instance ?: return
            a.runOnUiThread { if (!a.isFinishing) a.finish() }
        }
    }
}
