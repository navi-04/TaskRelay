package com.naveenraj.taskrelay

import android.content.Context
import android.provider.Settings
import java.time.ZoneId

/**
 * The `blocker*` methods of the native channel as plain functions that return channel-ready values (maps, lists, bytes). AlarmChannel
 * routes the calls here and does the replying; it runs the slow ones (listing apps, icons, saving) off the main thread.
 *
 * Everything stays on the device: the settings live in [BlockerStore], the app list and icons only travel to the Flutter UI.
 */
class BlockerChannel(context: Context) {
    private val app = context.applicationContext

    /** `blockerGetConfig`: the stored settings, normalised (see [BlockerConfig]). */
    fun getConfig(): Map<String, Any?> = Stores.blockerStore(app).read(InstalledApps.protectedExtras(app)).toMap()

    /**
     * `blockerSetConfig`: normalises [args] (the config map itself, or `{config: {...}}`), stores it, re-checks the app in front, and
     * returns what was stored, so the UI shows exactly what the blocker will use.
     */
    fun setConfig(args: Map<*, *>): Map<String, Any?> {
        val source = (args["config"] as? Map<*, *>) ?: args
        val config = BlockerConfig.fromMap(source, InstalledApps.protectedExtras(app))
        Stores.blockerStore(app).write(config)
        BlockerAccessibilityService.reevaluate(app)
        return config.toMap()
    }

    /**
     * `blockerStatus`: is the accessibility service switched on in system settings, is the blocker enabled, is there a snapshot of
     * TODAY (without one the blocker fails open), and the decision it would make right now.
     */
    fun status(): Map<String, Any?> {
        val zone = ZoneId.systemDefault()
        val nowMs = System.currentTimeMillis()
        val config = Stores.blockerStore(app).read(InstalledApps.protectedExtras(app))
        val today = Stores.todayCache(app).read()
        return mapOf(
            "serviceEnabled" to serviceEnabled(),
            "enabled" to config.enabled,
            "hasData" to (today != null && today.date == Times.localDate(nowMs, zone).toString()),
            "snapshotDate" to today?.date,
            "decision" to BlockerPolicy.decide(config, today, nowMs, zone).toMap(),
        )
    }

    /** `blockerListApps`: `[{package, label}]`, sorted by label, without the protected apps. */
    fun listApps(): List<Map<String, Any?>> = InstalledApps.list(app).map { it.toMap() }

    /** `blockerAppIcon`: a PNG of at most 96 x 96 px, or null. */
    fun appIcon(pkg: String): ByteArray? = InstalledApps.appIcon(app, pkg)

    /** Our service's id is in the enabled-accessibility-services list. */
    fun serviceEnabled(): Boolean = isServiceListed(
        Settings.Secure.getString(app.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES),
        app.packageName,
        BlockerAccessibilityService::class.java.name,
    )
}

/**
 * PURE: is `pkg/cls` listed in an `ENABLED_ACCESSIBILITY_SERVICES` value (`pkg/cls:pkg2/.Short:...`)? A class that starts with a
 * dot is relative to its package, which is how adb and some settings screens write it.
 */
internal fun isServiceListed(setting: String?, pkg: String, cls: String): Boolean =
    setting.orEmpty().split(':').any { entry ->
        val slash = entry.indexOf('/')
        if (slash <= 0) {
            false
        } else {
            val p = entry.substring(0, slash).trim()
            val c = entry.substring(slash + 1).trim().let { if (it.startsWith(".")) p + it else it }
            p == pkg && c == cls
        }
    }
