package com.naveenraj.taskrelay

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The Flutter host. It only wires the native channel ([AlarmChannel]) and records what launched it: a shared text (ACTION_SEND)
 * and the widget's "+" request. Dart pulls them with getInitialShare / getLaunchAction (cold start) or receives `onShare`
 * (warm start, from onNewIntent).
 */
class MainActivity : FlutterActivity() {
    private var alarmChannel: AlarmChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Notifications.ensureChannels(this)
        if (SessionStore.isSignedIn(this)) SyncWorker.schedulePeriodic(this) // KEEP policy: a no-op when already scheduled
        // Do not replay the launch intent when the task is restored (process death) or reopened from recents.
        val fromHistory = (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0
        if (savedInstanceState == null && !fromHistory) handleLaunchIntent(intent, warm = false)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        alarmChannel = AlarmChannel(this, flutterEngine.dartExecutor.binaryMessenger).also { it.register() }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        alarmChannel?.dispose()
        alarmChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent, warm = true)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        alarmChannel?.onPermissionsResult(requestCode, grantResults)
    }

    private fun handleLaunchIntent(intent: Intent?, warm: Boolean) {
        if (intent == null) return

        if (intent.getBooleanExtra(LaunchState.EXTRA_OPEN_ADD, false)) {
            LaunchState.setAction("add")
            intent.removeExtra(LaunchState.EXTRA_OPEN_ADD)
        }

        val share = LaunchState.parseShare(intent)
        if (share != null) {
            LaunchState.setShare(share)
            // consumed: do not let a later re-delivery of this very intent share it again
            intent.action = Intent.ACTION_MAIN
            intent.removeExtra(Intent.EXTRA_TEXT)
            intent.removeExtra(Intent.EXTRA_SUBJECT)
            if (warm) {
                // The app is running: push it. Only when Dart really handled the call is the pending copy dropped; if Dart is not
                // listening yet (notImplemented) or fails, getInitialShare still returns it.
                DartBridge.invoke("onShare", share.toMap(), object : MethodChannel.Result {
                    override fun success(result: Any?) = LaunchState.clearShareIf(share)
                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                    override fun notImplemented() = Unit
                })
            }
        }
    }
}
