package dev.nirang.client.network

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProxyIpCheckerTest {
    @Test
    fun `ip sb geo response keeps country code and city`() {
        val result = ProxyIpChecker.parseResponse(
            """{"ip":"213.165.41.160","country":"Netherlands","country_code":"nl","city":"Amsterdam"}""",
        )

        assertEquals("213.165.41.160", result.ip)
        assertEquals("NL", result.countryCode)
        assertEquals("Amsterdam", result.city)
    }

    @Test
    fun `plain IP response remains supported without extra API data`() {
        val result = ProxyIpChecker.parseResponse("2001:db8::1")

        assertEquals("2001:db8::1", result.ip)
        assertNull(result.countryCode)
        assertNull(result.city)
    }
}
