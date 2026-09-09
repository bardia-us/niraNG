package dev.nirang.client.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class UpdateInstallerTest {
    @Test
    fun semanticVersionComparisonIgnoresBuildSuffix() {
        assertTrue(UpdateInstaller.compareVersions("1.1.4+16", "1.1.3") > 0)
        assertEquals(0, UpdateInstaller.compareVersions("1.1.4+16", "v1.1.4"))
        assertTrue(UpdateInstaller.compareVersions("1.1.3", "1.1.4") < 0)
    }

    @Test
    fun `in-app update requires official URL size and SHA-256`() {
        val url = "https://github.com/bardia-us/niraNG/releases/download/v1.1.6/niraNG-v1.1.6-arm64-v8a.apk"
        UpdateInstaller.validateRequest(url, 1024, "a".repeat(64), "niraNG-v1.1.6-arm64-v8a.apk")
        assertThrows(IllegalArgumentException::class.java) {
            UpdateInstaller.validateRequest(url, 1024, null, "niraNG-v1.1.6-arm64-v8a.apk")
        }
    }
}
