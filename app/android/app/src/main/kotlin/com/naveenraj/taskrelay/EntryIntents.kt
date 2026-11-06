package com.naveenraj.taskrelay

import android.content.Intent

/** Puts every field on an Intent so a PendingIntent works without the store (after a restart, or a race with a re-plan). */
fun Entry.putExtras(intent: Intent): Intent = intent.apply {
    putExtra(Extras.KEY, key)
    putExtra(Extras.KIND, kind)
    putExtra(Extras.TASK_ID, taskId)
    putExtra(Extras.DATE, date)
    putExtra(Extras.LOCAL_TIME, localTime)
    putExtra(Extras.TITLE, title)
    putExtra(Extras.TRIGGER_MS, triggerMs)
    putExtra(Extras.ORIG_KIND, origKind)
}

/** Rebuilds an entry from a receiver / service / activity Intent (extras first, then the `taskrelay://.../<key>` data URI). */
fun Entry.Companion.fromIntent(intent: Intent?): Entry? {
    if (intent == null) return null
    val key = intent.getStringExtra(Extras.KEY)
        ?: intent.data?.path?.removePrefix("/")?.takeIf { it.isNotEmpty() }
        ?: return null
    val fromKey = fromKey(key)
    val kind = intent.getStringExtra(Extras.KIND) ?: fromKey?.kind ?: return null
    return Entry(
        key = key,
        kind = kind,
        taskId = intent.getStringExtra(Extras.TASK_ID) ?: fromKey?.taskId,
        date = intent.getStringExtra(Extras.DATE) ?: fromKey?.date ?: "",
        localTime = intent.getStringExtra(Extras.LOCAL_TIME) ?: fromKey?.localTime ?: "",
        title = intent.getStringExtra(Extras.TITLE) ?: fromKey?.title ?: "Reminder",
        triggerMs = intent.getLongExtra(Extras.TRIGGER_MS, 0L),
        origKind = intent.getStringExtra(Extras.ORIG_KIND) ?: fromKey?.origKind,
    )
}
