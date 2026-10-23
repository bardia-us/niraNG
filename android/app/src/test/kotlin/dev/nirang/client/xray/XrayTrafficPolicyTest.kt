package dev.nirang.client.xray

import dev.nirang.client.model.ServerRecord
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayTrafficPolicyTest {
    @Test
    fun `running core config enables outbound byte accounting without network stats API`() {
        val server = ServerRecord("test", "Test", "SE", "vless", "example.com", 443, "id", "tcp", "none", emptyMap())
        val config = JSONObject(XrayConfigBuilder.buildSafeFallbackConfig(server))
        assertTrue("stats manager must be enabled", config.has("stats"))
        val system = config.getJSONObject("policy").getJSONObject("system")
        assertTrue(system.getBoolean("statsOutboundUplink"))
        assertTrue(system.getBoolean("statsOutboundDownlink"))
        assertTrue("no localhost stats server is needed", !config.has("api"))
    }
}
