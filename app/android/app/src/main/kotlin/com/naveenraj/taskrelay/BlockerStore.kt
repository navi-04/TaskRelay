package com.naveenraj.taskrelay

import android.annotation.SuppressLint
import android.content.SharedPreferences

/**
 * The app blocker's settings as ONE JSON text in the private prefs file `taskrelay_blocker` (see [BlockerConfig] for the shape).
 * Device-local: not synced, not backed up (see the backup rules), wiped on sign-out. [read] normalises, so a hand-edited or
 * corrupt file can only ever produce a valid config (at worst the defaults: blocker off).
 *
 * commit() on purpose: the config must be on disk (or gone) before a caller moves on, and every caller is off the main thread.
 */
@SuppressLint("ApplySharedPref")
class BlockerStore(private val prefs: SharedPreferences) {

    /** The stored config (normalised). [extraProtected]: this device's extra protected packages, see [InstalledApps.protectedExtras]. */
    fun read(extraProtected: Set<String> = emptySet()): BlockerConfig =
        BlockerConfig.parse(prefs.getString(KEY, null), extraProtected)

    /** Stores [config] exactly as given; callers pass a config that came out of [BlockerConfig.fromMap] / [BlockerConfig.fromJson]. */
    fun write(config: BlockerConfig) {
        check(prefs.edit().putString(KEY, config.toJson().toString()).commit()) { "could not persist the blocker settings" }
    }

    /** Sign-out: nothing may survive. */
    fun clear() {
        prefs.edit().clear().commit()
    }

    companion object {
        const val PREFS = "taskrelay_blocker"
        private const val KEY = "config"
    }
}
