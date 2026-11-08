package com.naveenraj.taskrelay

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockerConfigTest {
    private fun parse(json: String, extra: Set<String> = emptySet()) = BlockerConfig.fromJson(JSONObject(json), extra)

    private val full = BlockerConfig(
        enabled = true,
        mode = BlockerConfig.MODE_SET_TIMES,
        countOverdue = false,
        unlockWhenDone = true,
        packages = listOf("com.instagram.android", "com.google.android.youtube"),
        windows = listOf(UseWindow("12:00", "13:00", listOf(1, 2, 3, 4, 5)), UseWindow("18:00", "20:30", listOf(6, 7))),
    )

    // ── defaults and the wire shape ─────────────────────────────────────────────────────────────────────────────

    @Test
    fun defaults() {
        val c = BlockerConfig()
        assertFalse(c.enabled)
        assertEquals("until_done", c.mode)
        assertTrue(c.countOverdue)
        assertFalse(c.unlockWhenDone)
        assertTrue(c.packages.isEmpty())
        assertTrue(c.windows.isEmpty())
        assertEquals(c, BlockerConfig.fromJson(JSONObject("{}")))
        assertEquals(c, BlockerConfig.fromJson(null))
    }

    @Test
    fun wireShapeIsSnakeCase() {
        val o = full.toJson()
        assertEquals(setOf("enabled", "mode", "count_overdue", "unlock_when_done", "packages", "windows"), o.keys().asSequence().toSet())
        assertEquals("set_times", o.getString("mode"))
        assertFalse(o.getBoolean("count_overdue"))
        assertEquals("com.instagram.android", o.getJSONArray("packages").getString(0))
        val w = o.getJSONArray("windows").getJSONObject(1)
        assertEquals(setOf("start", "end", "days"), w.keys().asSequence().toSet())
        assertEquals("18:00", w.getString("start"))
        assertEquals("20:30", w.getString("end"))
        assertEquals(JSONArray(listOf(6, 7)).toString(), w.getJSONArray("days").toString())
    }

    @Test
    fun jsonAndTextRoundTrip() {
        assertEquals(full, BlockerConfig.fromJson(full.toJson()))
        assertEquals(full, BlockerConfig.parse(full.toJson().toString()))
        assertEquals(BlockerConfig(), BlockerConfig.parse(BlockerConfig().toJson().toString()))
    }

    @Test
    fun mapRoundTrip_asTheChannelCarriesIt() {
        assertEquals(full, BlockerConfig.fromMap(full.toMap()))
        // the channel's own map types: nested HashMap / ArrayList of boxed values
        val fromDart = hashMapOf<Any?, Any?>(
            "enabled" to true,
            "mode" to "free_time",
            "count_overdue" to true,
            "unlock_when_done" to false,
            "packages" to arrayListOf<Any?>("com.example.a", "com.example.b"),
            "windows" to arrayListOf<Any?>(hashMapOf<Any?, Any?>("start" to "09:00", "end" to "10:00", "days" to arrayListOf<Any?>(1, 3))),
        )
        val c = BlockerConfig.fromMap(fromDart)
        assertEquals(BlockerConfig(true, "free_time", true, false, listOf("com.example.a", "com.example.b"), listOf(UseWindow("09:00", "10:00", listOf(1, 3)))), c)
    }

    @Test
    fun toMapUsesOnlyChannelTypes_noSets() {
        val m = full.toMap()
        assertTrue(m["packages"] is List<*>)
        val w = (m["windows"] as List<*>)[0] as Map<*, *>
        assertTrue(w["days"] is List<*>)
        assertEquals(listOf(1, 2, 3, 4, 5), w["days"])
    }

    // ── normalisation ───────────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun anUnknownModeBecomesUntilDone() {
        assertEquals("until_done", parse("""{"mode":"strict"}""").mode)
        assertEquals("until_done", parse("""{"mode":""}""").mode)
        assertEquals("until_done", parse("""{"mode":5}""").mode)
        assertEquals("until_done", parse("""{"mode":null}""").mode)
        for (m in listOf("until_done", "free_time", "set_times")) assertEquals(m, parse("""{"mode":"$m"}""").mode)
    }

    @Test
    fun packagesAreTrimmedDistinctAndNonBlank() {
        val c = parse("""{"packages":["  com.a.app ","com.a.app","","   ",null,7,"com.b.app"]}""")
        assertEquals(listOf("com.a.app", "com.b.app"), c.packages)
    }

    @Test
    fun protectedPackagesAreDropped() {
        val c = parse(
            """{"packages":["com.android.settings","com.naveenraj.taskrelay","com.google.android.dialer","com.android.phone",
                "com.android.systemui","com.example.launcher","com.instagram.android"]}""",
            extra = setOf("com.example.launcher"), // this device's launcher, as the channel passes it
        )
        assertEquals(listOf("com.instagram.android"), c.packages)
    }

    @Test
    fun atMost60Packages() {
        val many = JSONArray((1..70).map { "com.example.app$it" })
        val c = BlockerConfig.fromJson(JSONObject().put("packages", many))
        assertEquals(60, c.packages.size)
        assertEquals("com.example.app1", c.packages.first())
        assertEquals("com.example.app60", c.packages.last())
    }

    @Test
    fun windowsMustBeValidTimesWithTheEndAfterTheStart() {
        val c = parse(
            """{"windows":[
              {"start":"09:00","end":"10:00","days":[1]},
              {"start":"25:00","end":"26:00"},
              {"start":"9:30","end":"10:30"},
              {"start":"18:00","end":"18:00"},
              {"start":"22:00","end":"06:00"},
              {"start":"10:00"},
              {"end":"10:00"},
              "oops",
              {"start":"13:00","end":"14:15","days":[2]}
            ]}""",
        )
        assertEquals(listOf(UseWindow("09:00", "10:00", listOf(1)), UseWindow("13:00", "14:15", listOf(2))), c.windows)
    }

    @Test
    fun windowsAreSortedByStart() {
        val c = parse(
            """{"windows":[
              {"start":"18:00","end":"19:00"},{"start":"07:30","end":"08:00"},{"start":"12:00","end":"12:30"},{"start":"07:30","end":"07:45"}
            ]}""",
        )
        assertEquals(listOf("07:30" to "07:45", "07:30" to "08:00", "12:00" to "12:30", "18:00" to "19:00"), c.windows.map { it.start to it.end })
    }

    @Test
    fun atMost14Windows() {
        val many = JSONArray().also { a ->
            for (i in 0 until 20) a.put(JSONObject().put("start", Times.hhmm(i, 0)).put("end", Times.hhmm(i, 30)))
        }
        val c = BlockerConfig.fromJson(JSONObject().put("windows", many))
        assertEquals(14, c.windows.size)
        assertEquals("00:00", c.windows.first().start)
        assertEquals("13:00", c.windows.last().start)
    }

    @Test
    fun daysKeepOnlyOneToSevenSortedAndDistinct_emptyOrMissingMeansEveryDay() {
        val every = listOf(1, 2, 3, 4, 5, 6, 7)
        fun days(json: String) = parse("""{"windows":[{"start":"09:00","end":"10:00"$json}]}""").windows.single().days
        assertEquals(listOf(1, 3, 7), days(""","days":[7,0,3,3,1,8,-2]"""))
        assertEquals(every, days(""))
        assertEquals(every, days(""","days":[]"""))
        assertEquals(every, days(""","days":[0,9]""")) // nothing valid left: every day, like an empty list
        assertEquals(every, days(""","days":null"""))
        assertEquals(listOf(7), days(""","days":[7]""")) // Sunday
    }

    @Test
    fun windowTimesAreNormalisedToHhMm() {
        val c = parse("""{"windows":[{"start":" 09:00 ","end":"10:00:30"}]}""")
        assertEquals(UseWindow("09:00", "10:00", listOf(1, 2, 3, 4, 5, 6, 7)), c.windows.single())
    }

    @Test
    fun normalisingTwiceChangesNothing() {
        val messy = parse(
            """{"enabled":true,"mode":"nope","packages":[" a.b ","a.b","com.android.settings"],
              "windows":[{"start":"18:00","end":"19:00","days":[9]},{"start":"07:00","end":"08:00","days":[2,2]}]}""",
        )
        assertEquals(messy, BlockerConfig.fromJson(messy.toJson()))
        assertEquals(messy, BlockerConfig.fromMap(messy.toMap()))
    }

    // ── garbage never throws ────────────────────────────────────────────────────────────────────────────────────

    @Test
    fun garbageGivesDefaultsAndNeverThrows() {
        val defaults = BlockerConfig()
        assertEquals(defaults, BlockerConfig.parse(null))
        assertEquals(defaults, BlockerConfig.parse(""))
        assertEquals(defaults, BlockerConfig.parse("   "))
        assertEquals(defaults, BlockerConfig.parse("not json at all"))
        assertEquals(defaults, BlockerConfig.parse("[1,2,3]"))
        assertEquals(defaults, BlockerConfig.parse("{\"enabled\": tru"))
        assertEquals(defaults, BlockerConfig.fromMap(null))
        assertEquals(defaults, BlockerConfig.fromMap(emptyMap<String, Any?>()))
    }

    @Test
    fun wrongTypesAreTolerated() {
        val c = BlockerConfig.fromMap(
            mapOf(
                "enabled" to "yes",
                "mode" to 5,
                "count_overdue" to listOf(1),
                "packages" to "oops",
                "windows" to listOf(1, "x", mapOf("start" to null, "end" to 7), mapOf("start" to "09:00", "end" to "10:00", "days" to "mon")),
            ),
        )
        assertFalse(c.enabled)
        assertEquals("until_done", c.mode)
        assertTrue(c.countOverdue)
        assertTrue(c.packages.isEmpty())
        assertEquals(1, c.windows.size) // only the one valid window survives; its bad `days` means every day
        assertEquals(listOf(1, 2, 3, 4, 5, 6, 7), c.windows.single().days)
    }

    @Test
    fun theEnabledFlagIsReadAsABoolean() {
        assertTrue(parse("""{"enabled":true}""").enabled)
        assertFalse(parse("""{"enabled":false}""").enabled)
        assertFalse(parse("""{"enabled":null}""").enabled)
    }
}
