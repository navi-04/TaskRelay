package com.naveenraj.taskrelay

import android.content.SharedPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockerStoreTest {
    /** Just enough SharedPreferences for a store that keeps one string. */
    private class FakePrefs : SharedPreferences {
        val values = HashMap<String, Any?>()

        override fun getAll(): MutableMap<String, *> = values
        override fun getString(key: String?, defValue: String?): String? = values[key] as String? ?: defValue
        override fun getStringSet(key: String?, defValues: MutableSet<String>?): MutableSet<String>? = defValues
        override fun getInt(key: String?, defValue: Int): Int = defValue
        override fun getLong(key: String?, defValue: Long): Long = defValue
        override fun getFloat(key: String?, defValue: Float): Float = defValue
        override fun getBoolean(key: String?, defValue: Boolean): Boolean = defValue
        override fun contains(key: String?): Boolean = values.containsKey(key)
        override fun registerOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit
        override fun unregisterOnSharedPreferenceChangeListener(listener: SharedPreferences.OnSharedPreferenceChangeListener?) = Unit

        override fun edit(): SharedPreferences.Editor = object : SharedPreferences.Editor {
            private val pending = HashMap<String, Any?>()
            private var wipe = false

            override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                pending[key!!] = value
                return this
            }

            override fun putStringSet(key: String?, values: MutableSet<String>?): SharedPreferences.Editor = this
            override fun putInt(key: String?, value: Int): SharedPreferences.Editor = this
            override fun putLong(key: String?, value: Long): SharedPreferences.Editor = this
            override fun putFloat(key: String?, value: Float): SharedPreferences.Editor = this
            override fun putBoolean(key: String?, value: Boolean): SharedPreferences.Editor = this
            override fun remove(key: String?): SharedPreferences.Editor = this

            override fun clear(): SharedPreferences.Editor {
                wipe = true
                return this
            }

            override fun commit(): Boolean {
                if (wipe) values.clear()
                values.putAll(pending)
                return true
            }

            override fun apply() {
                commit()
            }
        }
    }

    private val config = BlockerConfig(
        enabled = true,
        mode = BlockerConfig.MODE_SET_TIMES,
        packages = listOf("com.instagram.android"),
        windows = listOf(UseWindow("18:00", "20:00", listOf(5, 6, 7))),
    )

    @Test
    fun nothingStoredMeansTheDefaults_blockerOff() {
        assertEquals(BlockerConfig(), BlockerStore(FakePrefs()).read())
        assertFalse(BlockerStore(FakePrefs()).read().enabled)
    }

    @Test
    fun writeThenReadGivesTheSameConfig() {
        val store = BlockerStore(FakePrefs())
        store.write(config)
        assertEquals(config, store.read())
    }

    @Test
    fun readNormalisesWhateverIsOnDisk() {
        val prefs = FakePrefs()
        prefs.values["config"] = """{"enabled":true,"mode":"nonsense","packages":["com.android.settings"," com.x.y ","com.x.y"],"windows":[{"start":"22:00","end":"06:00"}]}"""
        val c = BlockerStore(prefs).read()
        assertTrue(c.enabled)
        assertEquals("until_done", c.mode)
        assertEquals(listOf("com.x.y"), c.packages)
        assertTrue(c.windows.isEmpty())
        // a launcher this device found is dropped on load too
        prefs.values["config"] = """{"enabled":true,"packages":["com.some.launcher","com.x.y"]}"""
        assertEquals(listOf("com.x.y"), BlockerStore(prefs).read(extraProtected = setOf("com.some.launcher")).packages)
    }

    @Test
    fun corruptTextMeansTheDefaults() {
        val prefs = FakePrefs()
        prefs.values["config"] = "{ this is not json"
        assertEquals(BlockerConfig(), BlockerStore(prefs).read())
    }

    @Test
    fun clearWipesEverything() {
        val prefs = FakePrefs()
        val store = BlockerStore(prefs)
        store.write(config)
        store.clear()
        assertTrue(prefs.values.isEmpty())
        assertEquals(BlockerConfig(), store.read())
    }
}
