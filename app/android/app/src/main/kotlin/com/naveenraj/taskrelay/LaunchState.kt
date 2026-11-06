package com.naveenraj.taskrelay

import android.content.Intent

/**
 * Launch inputs that Dart pulls once (getInitialShare / getLaunchAction): the ACTION_SEND text that started the app and the
 * widget's "+" request. Held in memory only; consumed on read. A share that arrives while the app is running is pushed with
 * `onShare` and only kept here when Dart did not take it.
 */
object LaunchState {
    const val EXTRA_OPEN_ADD = "open_add"
    const val MAX_TEXT_CHARS = 20_000
    private const val MAX_SUBJECT_CHARS = 500

    data class Share(val subject: String?, val text: String?) {
        fun toMap(): Map<String, Any?> = mapOf("subject" to subject, "text" to text)
    }

    @Volatile
    private var share: Share? = null

    @Volatile
    private var action: String? = null

    /** The ACTION_SEND text/plain content of [intent], capped at 20,000 characters; null when it is not a share (or is empty). */
    fun parseShare(intent: Intent?): Share? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        val type = intent.type ?: return null
        if (!type.startsWith("text/")) return null
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(MAX_TEXT_CHARS)?.takeIf { it.isNotBlank() }
        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.take(MAX_SUBJECT_CHARS)?.takeIf { it.isNotBlank() }
        if (text == null && subject == null) return null
        return Share(subject, text)
    }

    fun setShare(s: Share?) {
        share = s
    }

    /** Consumed once. */
    fun takeShare(): Share? {
        val s = share
        share = null
        return s
    }

    /** Forget [s] only if it is still the pending one (Dart took it through onShare). */
    fun clearShareIf(s: Share) {
        if (share == s) share = null
    }

    fun setAction(a: String?) {
        action = a
    }

    /** "add" when the widget's "+" launched the app, consumed once. */
    fun takeAction(): String? {
        val a = action
        action = null
        return a
    }
}
