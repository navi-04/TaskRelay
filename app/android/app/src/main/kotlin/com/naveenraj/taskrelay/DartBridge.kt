package com.naveenraj.taskrelay

import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * native -> Dart calls on the shared channel. Only delivered while the Flutter engine / channel exists; when it does not
 * (process started by an alarm, widget or worker) the call is silently dropped, never a crash. Dart pulls the same state
 * on next launch (getSyncStatus, getInitialShare, ...).
 */
object DartBridge {
    private const val TAG = "DartBridge"

    @Volatile
    private var channel: MethodChannel? = null

    fun attach(c: MethodChannel) {
        channel = c
    }

    fun detach(c: MethodChannel) {
        if (channel === c) channel = null
    }

    val isAttached: Boolean get() = channel != null

    /** Posts to the main thread (MethodChannel requires the platform thread). [callback] is optional. */
    fun invoke(method: String, args: Any? = null, callback: MethodChannel.Result? = null) {
        if (channel == null) return
        Bg.main.post {
            try {
                channel?.invokeMethod(method, args, callback)
            } catch (t: Throwable) {
                Log.w(TAG, "invoke $method failed: ${t.javaClass.simpleName}")
            }
        }
    }

    fun actionsChanged() = invoke("onActionsChanged")

    fun syncFinished(ok: Boolean, errorCode: String?) =
        invoke("onSyncFinished", mapOf("ok" to ok, "errorCode" to errorCode))
}
