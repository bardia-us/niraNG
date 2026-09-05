package dev.nirang.client.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PerAppPolicyTest {
    private val ownPackage = "dev.nirang.client"
    private val installed = setOf("app.one", "app.two", ownPackage)

    @Test
    fun `selected mode routes only installed selected applications`() {
        val rules = PerAppPolicy.resolve(
            "selected",
            setOf("app.one", "removed.app", ownPackage),
            installed,
            ownPackage,
        )

        assertEquals(setOf("app.one"), rules.allowed)
        assertTrue(rules.disallowed.isEmpty())
    }

    @Test
    fun `selected mode safely falls back when all selected apps were removed`() {
        val rules = PerAppPolicy.resolve(
            "selected",
            setOf("removed.app"),
            installed,
            ownPackage,
        )

        assertTrue(rules.fellBackToAllApps)
        assertEquals(setOf(ownPackage), rules.disallowed)
    }

    @Test
    fun `exclude mode always excludes niraNG and selected installed apps`() {
        val rules = PerAppPolicy.resolve(
            "exclude",
            setOf("app.two", "removed.app"),
            installed,
            ownPackage,
        )

        assertEquals(setOf("app.two", ownPackage), rules.disallowed)
    }
}
