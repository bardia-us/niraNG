package dev.nirang.client.ping

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CustomProbeConfigTest {
    @Test fun `Xray probe keeps full routing DNS and chain but replaces TUN and fixed listeners`() {
        val raw = """{"inbounds":[{"protocol":"tun","tag":"original-tun","settings":{"mtu":1400}},{"protocol":"socks","tag":"old","listen":"127.0.0.1","port":10808}],"dns":{"servers":["1.1.1.1"]},"routing":{"rules":[{"type":"field","inboundTag":["original-tun"],"outboundTag":"chain"}]},"outbounds":[{"protocol":"freedom","tag":"chain"}]}"""
        val original = JSONObject(raw)
        val probe = JSONObject(CustomProbeConfig.xray(raw, 39123))
        assertEquals(original.getJSONObject("routing").toString(), probe.getJSONObject("routing").toString())
        assertEquals(original.getJSONObject("dns").toString(), probe.getJSONObject("dns").toString())
        assertEquals(original.getJSONArray("outbounds").toString(), probe.getJSONArray("outbounds").toString())
        assertEquals(1, probe.getJSONArray("inbounds").length())
        val input = probe.getJSONArray("inbounds").getJSONObject(0)
        assertEquals("original-tun", input.getString("tag"))
        assertEquals("socks", input.getString("protocol")); assertEquals(39123,input.getInt("port"))
    }

    @Test fun `valid untagged Xray TUN also supports isolated delay`() {
        val raw = """{"inbounds":[{"protocol":"tun","settings":{}}],"outbounds":[{"protocol":"freedom"}]}"""
        val probe = JSONObject(CustomProbeConfig.xray(raw,39125))
        // Runtime metering assigns a stable tag to originally untagged inputs. The probe
        // must retain that identity rather than bypassing inbound-dependent routing.
        val prepared=JSONObject(dev.nirang.client.subscription.CustomXrayConfig.prepare(raw,true))
        assertEquals(prepared.getJSONArray("inbounds").getJSONObject(0).getString("tag"),
            probe.getJSONArray("inbounds").getJSONObject(0).getString("tag"))
    }

    @Test fun `sing box probe retains full route and DNS with original TUN tag`() {
        val raw = """{"inbounds":[{"type":"tun","tag":"original-tun","auto_route":true,"address":["172.19.0.1/30"]}],"route":{"auto_detect_interface":true,"final":"proxy"},"dns":{"servers":[{"type":"udp","server":"1.1.1.1","tag":"dns"}]},"outbounds":[{"type":"direct","tag":"proxy"}]}"""
        val original = JSONObject(raw)
        val probe = JSONObject(CustomProbeConfig.singBox(raw,39124,"/private/operation/cache.db"))
        assertEquals(original.getJSONObject("route").toString(),probe.getJSONObject("route").toString())
        assertEquals(original.getJSONObject("dns").toString(),probe.getJSONObject("dns").toString())
        val input = probe.getJSONArray("inbounds").getJSONObject(0)
        assertEquals("original-tun", input.getString("tag")); assertEquals("socks", input.getString("type"))
        assertEquals(39124,input.getInt("listen_port"))
        assertEquals("/private/operation/cache.db",probe.getJSONObject("experimental").getJSONObject("cache_file").getString("path"))
    }

    @Test fun `private leases reserve distinct available ports until handoff`() {
        PrivateProbePorts.reserve(3).use { ports ->
            assertEquals(3,ports.ports.toSet().size)
            assertTrue(ports.ports.all { it in 1024..65535 && it !in setOf(10808,10809,10819,10821) })
            assertThrows(java.net.BindException::class.java) { java.net.ServerSocket(ports.ports.first(),1,java.net.InetAddress.getByName("127.0.0.1")).close() }
        }
    }
}
