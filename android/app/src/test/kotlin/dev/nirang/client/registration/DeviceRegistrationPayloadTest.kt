package dev.nirang.client.registration

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

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
            appBuild = 20,
            firstSeen = "2026-08-28T12:00:00.000Z",
            lastSeen = "2026-08-28T13:00:00.000Z",
            requestTimestamp = 1_788_000_000L,
            nonce = "abcdefghijklmnopqrstuv",
        )

        assertEquals("android", payload.getString("platform"))
        assertEquals("niraNG", payload.getString("app_name"))
        assertEquals("Samsung", payload.getString("manufacturer"))
        assertEquals("Galaxy S24 5G", payload.getString("model"))
        assertEquals(7, payload.getInt("schema_version"))
        assertEquals(20, payload.getInt("app_build"))
        assertEquals("a".repeat(64), payload.getString("device_key"))
        assertTrue(payload.getLong("request_timestamp") > 0)
        assertTrue(payload.getString("request_nonce").matches(Regex("[A-Za-z0-9_-]{22}")))
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

    @Test
    fun `blocked state does not depend on administrator reason text`() {
        val response = JSONObject()
            .put("blocked", true)
            .put("reason", "Contact support for details")

        assertEquals(
            RemoteAccessState.BLOCKED,
            DeviceRegistrationManager.classifyAccessState(403, response),
        )
    }

    @Test
    fun `minimum version denial remains distinct from a block`() {
        val response = JSONObject().put("update_required", true)

        assertEquals(
            RemoteAccessState.OUTDATED,
            DeviceRegistrationManager.classifyAccessState(426, response),
        )
    }
}
