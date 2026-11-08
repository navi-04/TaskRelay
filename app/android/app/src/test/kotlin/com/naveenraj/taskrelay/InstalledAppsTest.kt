package com.naveenraj.taskrelay

import com.naveenraj.taskrelay.InstalledApps.App
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InstalledAppsTest {

    @Test
    fun everyFixedProtectedPackageIsProtected() {
        val fixed = listOf(
            "com.naveenraj.taskrelay",
            "com.android.settings",
            "com.android.systemui",
            "com.android.phone",
            "com.android.dialer",
            "com.google.android.dialer",
            "com.android.emergency",
            "com.android.contacts",
            "com.google.android.contacts",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.google.android.permissioncontroller",
            "com.android.permissioncontroller",
        )
        for (p in fixed) assertTrue(p, InstalledApps.isProtected(p))
        assertEquals(fixed.toSet(), InstalledApps.PROTECTED)
    }

    @Test
    fun ordinaryAppsAreNotProtected() {
        for (p in listOf("com.instagram.android", "com.google.android.youtube", "com.whatsapp", "com.android.chrome", "com.android.vending", "")) {
            assertFalse(p, InstalledApps.isProtected(p))
        }
    }

    @Test
    fun deviceSpecificPackagesAreProtectedThroughExtra() {
        val extra = setOf("com.google.android.apps.nexuslauncher", "com.samsung.android.honeyboard")
        assertFalse(InstalledApps.isProtected("com.google.android.apps.nexuslauncher"))
        assertTrue(InstalledApps.isProtected("com.google.android.apps.nexuslauncher", extra))
        assertTrue(InstalledApps.isProtected("com.samsung.android.honeyboard", extra))
        assertTrue(InstalledApps.isProtected("com.android.settings", extra)) // the fixed list still applies
        assertFalse(InstalledApps.isProtected("com.instagram.android", extra))
    }

    @Test
    fun theProtectedMatchIsExact_notAPrefix() {
        assertFalse(InstalledApps.isProtected("com.android.settings.evil"))
        assertFalse(InstalledApps.isProtected("com.android"))
        assertFalse(InstalledApps.isProtected("COM.ANDROID.SETTINGS"))
    }

    @Test
    fun keyboardPackagesAreReadFromTheSecureSetting() {
        val setting = "com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME:" +
            "com.samsung.android.honeyboard/.service.HoneyBoardService;1234567;89"
        assertEquals(setOf("com.google.android.inputmethod.latin", "com.samsung.android.honeyboard"), InstalledApps.inputMethodPackages(setting))
        assertEquals(setOf("com.google.android.inputmethod.latin"), InstalledApps.inputMethodPackages("com.google.android.inputmethod.latin/.LatinIME"))
        assertEquals(emptySet<String>(), InstalledApps.inputMethodPackages(null))
        assertEquals(emptySet<String>(), InstalledApps.inputMethodPackages(""))
        assertEquals(emptySet<String>(), InstalledApps.inputMethodPackages("no-slash-here:/also-no-package"))
    }

    @Test
    fun curateDropsProtectedAndDuplicates_andSortsByLabelIgnoringCase() {
        val raw = listOf(
            App("com.youtube", "YouTube"),
            App("com.android.settings", "Settings"),
            App("com.instagram", "instagram"),
            App("com.android.vending", "Play Store"),
            App("com.youtube", "YouTube (second launcher entry)"),
            App("com.launcher", "Home"),
            App("com.naveenraj.taskrelay", "TaskRelay"),
            App("com.apple.like", "Apple like"),
        )
        val out = InstalledApps.curate(raw, extra = setOf("com.launcher"))
        assertEquals(listOf("Apple like", "instagram", "Play Store", "YouTube"), out.map { it.label })
        assertEquals(listOf("com.apple.like", "com.instagram", "com.android.vending", "com.youtube"), out.map { it.packageName })
    }

    @Test
    fun curateKeepsTheFirstEntryOfADuplicatePackage_andNamesUnlabelledAppsByPackage() {
        val out = InstalledApps.curate(listOf(App("com.b", "Same"), App("com.a", "Same"), App("com.c", "  "), App("com.b", "Other")))
        assertEquals(listOf("com.a", "com.b", "com.c"), out.map { it.packageName }.sorted()) // one entry per package
        assertEquals("Same", out.first { it.packageName == "com.b" }.label)
        assertEquals("com.c", out.first { it.packageName == "com.c" }.label)
        // equal labels: ordered by package, so the list is stable between calls
        assertEquals(listOf("com.a", "com.b"), out.filter { it.label == "Same" }.map { it.packageName })
    }

    @Test
    fun appMapHasThePackageAndLabelKeys() {
        assertEquals(mapOf("package" to "com.x", "label" to "X"), App("com.x", "X").toMap())
    }
}
