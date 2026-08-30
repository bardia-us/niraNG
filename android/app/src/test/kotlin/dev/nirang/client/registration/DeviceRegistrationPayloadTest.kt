package dev.nirang.client.registration

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DeviceRegistrationPayloadTest {
    @Test
    fun `Android registration contains only disclosed installation metadata`() {
        val payload = DeviceRegistrationManager.buildPayload(
            installationId = "12345678-1234-4123-8123-123456789abc",
            deviceKey = "a".repeat(64),
            deviceName = "Bardia's S24",
            manufacturer = "Samsung",
            model = "Galaxy S24 5G",
            osVersion = "Android 16 (SDK 36)",
            appVersion = "1.0.9",
            firstSeen = "2026-08-28T12:00:00.000Z",
            lastSeen = "2026-08-28T13:00:00.000Z",
        )

        assertEquals("android", payload.getString("platform"))
        assertEquals("niraNG", payload.getString("app_name"))
        assertEquals("Samsung", payload.getString("manufacturer"))
        assertEquals("Galaxy S24 5G", payload.getString("model"))
        assertEquals(4, payload.getInt("schema_version"))
        assertEquals("a".repeat(64), payload.getString("device_key"))
        for (forbidden in listOf("imei", "serial", "mac", "android_id", "sim", "ssid", "contacts")) {
            assertFalse(payload.has(forbidden))
        }
    }

    @Test
    fun `device key is stable scoped and never contains raw Android ID`() {
        val androidId = "0123456789abcdef"
        val first = DeviceRegistrationManager.deriveDeviceKey(androidId)
        val second = DeviceRegistrationManager.deriveDeviceKey(androidId.uppercase())
        val otherPackage = DeviceRegistrationManager.deriveDeviceKey(androidId, "dev.other.app")

        assertEquals(first, second)
        assertEquals(64, first.length)
        assertTrue(first.matches(Regex("[0-9a-f]{64}")))
        assertFalse(first.contains(androidId))
        assertNotEquals(first, otherPackage)
    }
}
