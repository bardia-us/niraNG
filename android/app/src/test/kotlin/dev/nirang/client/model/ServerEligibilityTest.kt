package dev.nirang.client.model

import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ServerEligibilityTest {
    @Test
    fun `subscription notice entries fail fast`() {
        assertNotNull(ServerEligibility.rejectionReason(server("هر دفعه آپدیت کنید - V8.8", "1.1.1.1")))
    }

    @Test
    fun `ordinary server remains connectable`() {
        assertNull(ServerEligibility.rejectionReason(server("Netherlands", "nl.example.com")))
    }

    private fun server(name: String, address: String) = ServerRecord(
        id = "id",
        name = name,
        country = "NL",
        protocol = "vless",
        address = address,
        port = 443,
        credential = "00000000-0000-0000-0000-000000000000",
        transport = "tcp",
        security = "tls",
        parameters = emptyMap(),
    )
}
