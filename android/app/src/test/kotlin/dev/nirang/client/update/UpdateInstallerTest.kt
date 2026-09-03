package dev.nirang.client.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class UpdateInstallerTest {
    @Test
    fun semanticVersionComparisonIgnoresBuildSuffix() {
        assertTrue(UpdateInstaller.compareVersions("1.1.4+16", "1.1.3") > 0)
        assertEquals(0, UpdateInstaller.compareVersions("1.1.4+16", "v1.1.4"))
        assertTrue(UpdateInstaller.compareVersions("1.1.3", "1.1.4") < 0)
    }
}
