package dev.nirang.client.cores.singbox

import org.junit.Assert.*
import org.junit.Test

class SingBoxAppPolicyTest {
    private val own = "dev.nirang.client"
    @Test fun allAppsAndExclusionsAlwaysBypassOwnApp() {
        assertEquals(setOf(own), SingBoxAppPolicy.resolve(emptySet(), emptySet(), own).disallowed)
        assertEquals(setOf(own, "browser.app"), SingBoxAppPolicy.resolve(emptySet(), setOf("browser.app"), own).disallowed)
    }
    @Test fun explicitIncludesPreserveAuthorScopeWithoutOwnApp() {
        val rules = SingBoxAppPolicy.resolve(setOf(own, "browser.app"), emptySet(), own)
        assertEquals(setOf("browser.app"), rules.allowed)
        assertTrue(rules.disallowed.isEmpty())
    }
    @Test fun ownOnlyIncludeNeverFallsBackToAllApps() {
        assertThrows(IllegalArgumentException::class.java) { SingBoxAppPolicy.resolve(setOf(own), emptySet(), own) }
    }
}
