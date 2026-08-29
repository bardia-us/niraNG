package dev.nirang.client.registration

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class DeviceRegistrationPayloadTest {
    @Test
    fun `Android registration contains only disclosed installation metadata`() {
        val payload = DeviceRegistrationManager.buildPayload(
            installationId = "12345678-1234-4123-8123-123456789abc",
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
        for (forbidden in listOf("imei", "serial", "mac", "android_id", "sim", "ssid", "contacts")) {
            assertFalse(payload.has(forbidden))
        }
    }
}
