package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject

/** A use window: the blocked apps may be used from [start] (inclusive) to [end] (exclusive) on [days] (ISO: 1 = Monday .. 7 = Sunday). */
data class UseWindow(val start: String, val end: String, val days: List<Int>) {
    /** The window as minutes since midnight; null unless it is a valid range inside one day. */
    val span: TimeBlock.Span?
        get() {
            val s = TimeBlock.toMinutes(start) ?: return null
            val e = TimeBlock.toMinutes(end) ?: return null
            return if (e > s) TimeBlock.Span(s, e) else null
        }

    /** True on [isoDay]; an empty list means every day. */
    fun appliesOn(isoDay: Int): Boolean = days.isEmpty() || isoDay in days
}

/**
 * The app blocker's settings. Device-local: they live in [BlockerStore] and are never sent to the server. This is also the wire
 * shape of the channel methods `blockerGetConfig` / `blockerSetConfig` (snake_case):
 *
 *     { "enabled": false, "mode": "until_done" | "free_time" | "set_times", "count_overdue": true, "unlock_when_done": false,
 *       "packages": ["com.example.app"], "windows": [{ "start": "18:00", "end": "20:00", "days": [1, 2, 3, 4, 5] }] }
 *
 * Whatever comes in (a channel map, a stored JSON text) is NORMALISED by [fromJson] / [fromMap] / [parse]; they never throw:
 *  - an unknown mode becomes `until_done`;
 *  - packages: trimmed, non-blank, distinct, the protected ones dropped (see [InstalledApps.isProtected]), at most 60;
 *  - windows: valid "HH:mm", end after start on the same day (no overnight), at most 14, sorted by start; `days` keeps 1..7 only,
 *    and an empty, missing or all-invalid list means every day (stored as 1..7).
 */
data class BlockerConfig(
    val enabled: Boolean = false,
    val mode: String = MODE_UNTIL_DONE,
    val countOverdue: Boolean = true,
    val unlockWhenDone: Boolean = false,
    val packages: List<String> = emptyList(),
    val windows: List<UseWindow> = emptyList(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("enabled", enabled)
        put("mode", mode)
        put("count_overdue", countOverdue)
        put("unlock_when_done", unlockWhenDone)
        put("packages", JSONArray(packages))
        put("windows", JSONArray().also { a ->
            windows.forEach { w ->
                a.put(JSONObject().apply {
                    put("start", w.start)
                    put("end", w.end)
                    put("days", JSONArray(w.days))
                })
            }
        })
    }

    /** The same shape as plain maps / lists for the MethodChannel (only List, never Set: the codec has no Set). */
    fun toMap(): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "mode" to mode,
        "count_overdue" to countOverdue,
        "unlock_when_done" to unlockWhenDone,
        "packages" to packages,
        "windows" to windows.map { mapOf("start" to it.start, "end" to it.end, "days" to it.days) },
    )

    companion object {
        const val MODE_UNTIL_DONE = "until_done"
        const val MODE_FREE_TIME = "free_time"
        const val MODE_SET_TIMES = "set_times"
        const val MAX_PACKAGES = 60
        const val MAX_WINDOWS = 14

        private val MODES = setOf(MODE_UNTIL_DONE, MODE_FREE_TIME, MODE_SET_TIMES)
        private val EVERY_DAY = listOf(1, 2, 3, 4, 5, 6, 7)

        /**
         * Normalises [o]. [extraProtected] are the packages that are protected on THIS device on top of the fixed list (the launcher,
         * the keyboards ...); the channel passes them, pure callers need not.
         */
        fun fromJson(o: JSONObject?, extraProtected: Set<String> = emptySet()): BlockerConfig {
            if (o == null) return BlockerConfig()
            val d = BlockerConfig()
            return BlockerConfig(
                enabled = o.optBoolean("enabled", d.enabled),
                mode = Json.str(o, "mode")?.takeIf { it in MODES } ?: d.mode,
                countOverdue = o.optBoolean("count_overdue", d.countOverdue),
                unlockWhenDone = o.optBoolean("unlock_when_done", d.unlockWhenDone),
                packages = packages(o.optJSONArray("packages"), extraProtected),
                windows = windows(o.optJSONArray("windows")),
            )
        }

        /** [m] as it arrives from the channel (nested maps / lists); anything that cannot be read gives the defaults. */
        fun fromMap(m: Map<*, *>?, extraProtected: Set<String> = emptySet()): BlockerConfig {
            if (m == null) return BlockerConfig()
            val o = try {
                JSONObject(m)
            } catch (_: Exception) {
                return BlockerConfig()
            }
            return fromJson(o, extraProtected)
        }

        /** The stored JSON text; missing or corrupt text gives the defaults (blocker off). */
        fun parse(text: String?, extraProtected: Set<String> = emptySet()): BlockerConfig = try {
            if (text.isNullOrBlank()) BlockerConfig() else fromJson(JSONObject(text), extraProtected)
        } catch (_: Exception) {
            BlockerConfig()
        }

        private fun packages(a: JSONArray?, extraProtected: Set<String>): List<String> {
            if (a == null) return emptyList()
            val out = LinkedHashSet<String>()
            for (i in 0 until a.length()) {
                val p = (a.opt(i) as? String)?.trim() ?: continue
                if (p.isEmpty() || InstalledApps.isProtected(p, extraProtected)) continue
                out.add(p)
                if (out.size >= MAX_PACKAGES) break
            }
            return out.toList()
        }

        private fun windows(a: JSONArray?): List<UseWindow> {
            val out = ArrayList<UseWindow>()
            for (w in Json.objects(a)) {
                val start = Json.str(w, "start")?.trim()?.let { Times.normalizeTime(it) } ?: continue
                val end = Json.str(w, "end")?.trim()?.let { Times.normalizeTime(it) } ?: continue
                val window = UseWindow(start, end, days(w.optJSONArray("days")))
                if (window.span == null) continue // the end must be after the start, on the same day
                out.add(window)
                if (out.size >= MAX_WINDOWS) break
            }
            return out.sortedWith(compareBy({ it.span?.start }, { it.span?.end })) // stable: equal windows keep their order
        }

        private fun days(a: JSONArray?): List<Int> {
            if (a == null) return EVERY_DAY
            val kept = java.util.TreeSet<Int>()
            for (i in 0 until a.length()) {
                val day = a.optInt(i, 0)
                if (day in 1..7) kept.add(day)
            }
            return if (kept.isEmpty()) EVERY_DAY else kept.toList()
        }
    }
}
