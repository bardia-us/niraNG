package dev.nirang.client.xray

import java.util.Base64
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayCoreEnvironmentTest {
    @Test
    fun `niraNG leaves XUDP BaseKey unset during actual core environment initialization`() {
        var receivedPath: String? = null
        var receivedXudpBaseKey: String? = null

        initializeCoreEnvironment("/android/files") { path, key ->
            receivedPath = path
            receivedXudpBaseKey = key
        }

        assertEquals("/android/files", receivedPath)
        assertTrue(receivedXudpBaseKey?.isEmpty() == true)
    }

    @Test
    fun `installation UUID is demonstrably not a valid XUDP BaseKey`() {
        val installationId = UUID.fromString("12345678-1234-4123-8123-123456789abc").toString()
        val decoded = Base64.getUrlDecoder().decode(installationId)

        assertEquals(27, decoded.size)
        assertTrue(decoded.size != REQUIRED_XUDP_KEY_BYTES)
    }

    private companion object {
        const val REQUIRED_XUDP_KEY_BYTES = 32
    }
}
