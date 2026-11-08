package com.naveenraj.taskrelay

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BlockerChannelTest {
    private val pkg = "com.naveenraj.taskrelay"
    private val cls = "com.naveenraj.taskrelay.BlockerAccessibilityService"

    @Test
    fun theFullServiceIdIsFound() {
        assertTrue(isServiceListed("$pkg/$cls", pkg, cls))
    }

    @Test
    fun theShortFormWithALeadingDotIsFound() {
        assertTrue(isServiceListed("$pkg/.BlockerAccessibilityService", pkg, cls))
    }

    @Test
    fun itIsFoundAmongOtherServices() {
        val setting = "com.other.app/com.other.app.ReaderService:$pkg/$cls:com.third/.Svc"
        assertTrue(isServiceListed(setting, pkg, cls))
        assertTrue(isServiceListed("com.other.app/.A:$pkg/.BlockerAccessibilityService", pkg, cls))
    }

    @Test
    fun otherServicesAndEmptySettingsAreNotUs() {
        assertFalse(isServiceListed(null, pkg, cls))
        assertFalse(isServiceListed("", pkg, cls))
        assertFalse(isServiceListed("com.other.app/com.other.app.ReaderService", pkg, cls))
        assertFalse(isServiceListed("$pkg/$pkg.SomeOtherService", pkg, cls))
        assertFalse(isServiceListed("$pkg/.SomeOtherService", pkg, cls))
        assertFalse(isServiceListed("com.other.app/$cls", pkg, cls)) // our class name under another package is not ours
        assertFalse(isServiceListed("$pkg", pkg, cls)) // no class at all
        assertFalse(isServiceListed("/$cls", pkg, cls)) // no package at all
    }
}
