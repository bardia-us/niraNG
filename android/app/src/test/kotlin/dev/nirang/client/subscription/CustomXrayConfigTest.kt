package dev.nirang.client.subscription

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class CustomXrayConfigTest {
    private val raw = """{"dns":{"servers":["https://dns.example/dns-query"]},"routing":{"domainStrategy":"IPIfNonMatch","rules":[]},"outbounds":[{"tag":"my-exit","protocol":"freedom"}],"customUnknown":{"keep":true}}"""
    @Test fun `Android adapter only supplies tunnel and loopback inputs`() {
        val result = JSONObject(CustomXrayConfig.prepare(raw, true))
        val source = JSONObject(raw)
        for (key in listOf("dns","routing","outbounds","customUnknown")) assertEquals(source.get(key).toString(),result.get(key).toString())
        val inbounds = result.getJSONArray("inbounds")
        assertEquals(3,inbounds.length())
        assertEquals("tun",inbounds.getJSONObject(0).getString("protocol"))
        assertEquals("xray0",inbounds.getJSONObject(0).getJSONObject("settings").getString("name"))
        assertEquals("127.0.0.1",inbounds.getJSONObject(1).getString("listen"))
    }
    @Test fun `proxy mode never creates a tun`() {
        val result = JSONObject(CustomXrayConfig.prepare(raw,false))
        assertEquals(2,result.getJSONArray("inbounds").length())
    }
    @Test fun `runtime telemetry counts inbound bytes while preserving user routing dns policy and tags`() {
        val source = JSONObject(raw).put("stats",JSONObject().put("existing",true))
            .put("policy",JSONObject().put("levels",JSONObject().put("7",JSONObject().put("handshake",9)))
                .put("system",JSONObject().put("statsOutboundUplink",false).put("statsInboundUplink",false)))
            .put("inbounds",org.json.JSONArray("""[{"tag":"user,tag;>>>traffic","protocol":"socks","listen":"127.0.0.1","port":10808,"settings":{"auth":"noauth"}},{"protocol":"http","listen":"127.0.0.1","port":10809}]"""))
        val result = JSONObject(CustomXrayConfig.prepare(source.toString(),true))
        val system = result.getJSONObject("policy").getJSONObject("system")
        assertTrue(system.getBoolean("statsInboundUplink"))
        assertTrue(system.getBoolean("statsInboundDownlink"))
        assertFalse(system.getBoolean("statsOutboundUplink"))
        assertEquals(source.getJSONObject("policy").getJSONObject("levels").toString(),result.getJSONObject("policy").getJSONObject("levels").toString())
        assertEquals(source.getJSONObject("routing").toString(),result.getJSONObject("routing").toString())
        assertEquals(source.getJSONObject("dns").toString(),result.getJSONObject("dns").toString())
        assertEquals(source.getJSONArray("outbounds").toString(),result.getJSONArray("outbounds").toString())
        assertEquals("user,tag;>>>traffic",result.getJSONArray("inbounds").getJSONObject(0).getString("tag"))
        val tags = (0 until result.getJSONArray("inbounds").length()).map { result.getJSONArray("inbounds").getJSONObject(it).getString("tag") }
        assertTrue(tags.all(String::isNotEmpty))
        assertEquals(tags.size,tags.toSet().size)
        assertTrue(result.getJSONObject("stats").getBoolean("existing"))
        assertFalse(source.getJSONObject("policy").getJSONObject("system").getBoolean("statsInboundUplink"))
    }
    @Test fun `telemetry assigns unique tags without colliding with custom tags and remains idempotent`() {
        val source = JSONObject(raw).put("inbounds",org.json.JSONArray("""[{"tag":"nirang-meter-1","protocol":"http","listen":"127.0.0.1","port":10810},{"protocol":"http","listen":"127.0.0.1","port":10811}]"""))
        val first = CustomXrayConfig.prepare(source.toString(),true)
        assertEquals(first,CustomXrayConfig.prepare(first,true))
        val inputs=JSONObject(first).getJSONArray("inbounds")
        val tags=(0 until inputs.length()).map {inputs.getJSONObject(it).getString("tag")}
        assertEquals(tags.size,tags.toSet().size)
        assertTrue(tags.all(String::isNotEmpty))
    }
    @Test fun `meter tags cannot activate previously unmatched inbound routing rules`() {
        val source = JSONObject(raw)
        source.getJSONObject("routing").put("rules",org.json.JSONArray("""[{"type":"field","inboundTag":["nirang-meter-1","nirang-meter-2"],"outboundTag":"my-exit"}]"""))
        source.put("inbounds",org.json.JSONArray("""[{"protocol":"http","listen":"127.0.0.1","port":10810}]"""))
        val result=JSONObject(CustomXrayConfig.prepare(source.toString(),true))
        val inputs=result.getJSONArray("inbounds")
        for(index in 0 until inputs.length()) {
            assertFalse(inputs.getJSONObject(index).getString("tag") in setOf("nirang-meter-1","nirang-meter-2"))
        }
        assertEquals(source.getJSONObject("routing").toString(),result.getJSONObject("routing").toString())
    }
    @Test fun `meter tags also reserve comma-separated routing inbound references supported by pinned core`() {
        val source=JSONObject(raw).put("inbounds",org.json.JSONArray("""[{"protocol":"http","listen":"127.0.0.1","port":10810}]"""))
        source.getJSONObject("routing").put("rules",org.json.JSONArray("""[{"type":"field","inboundTag":"nirang-meter-1,nirang-meter-2","outboundTag":"my-exit"}]"""))
        val result=JSONObject(CustomXrayConfig.prepare(source.toString(),true))
        assertEquals("nirang-meter-3",result.getJSONArray("inbounds").getJSONObject(0).getString("tag"))
        assertEquals(source.getJSONObject("routing").toString(),result.getJSONObject("routing").toString())
    }
    @Test fun `a valid near-limit source remains valid when its runtime copy is revalidated`() {
        val source=JSONObject(raw).put("padding", "x".repeat(CustomProfileCodec.MAX_PAYLOAD_BYTES-raw.length-20)).toString()
        assertTrue(source.toByteArray().size <= CustomProfileCodec.MAX_PAYLOAD_BYTES)
        val runtime=CustomXrayConfig.prepare(source,true)
        assertTrue(runtime.toByteArray().size > CustomProfileCodec.MAX_PAYLOAD_BYTES)
        assertEquals(runtime,CustomXrayConfig.prepareRuntime(runtime,true))
        try { CustomXrayConfig.prepare(runtime,true);fail("External source size limit was relaxed") }
        catch (_:IllegalArgumentException) { }
    }
    @Test fun `VPN accounting selects only the real TUN entrance and excludes auxiliary loopback chains`() {
        val source=JSONObject(raw).put("inbounds",org.json.JSONArray("""[{"tag":"actual,tun;>>>","protocol":"tun","settings":{"mtu":1400}},{"tag":"chain-helper","protocol":"socks","listen":"127.0.0.1","port":10810}]"""))
        val runtime=CustomXrayConfig.prepare(source.toString(),true)
        val selected=org.json.JSONArray(CustomXrayConfig.trafficInboundTags(runtime,true))
        assertEquals(1,selected.length())
        assertEquals("actual,tun;>>>",selected.getString(0))
    }
    @Test fun `proxy accounting selects app proxy entrances without auxiliary custom listeners`() {
        val source=JSONObject(raw).put("inbounds",org.json.JSONArray("""[{"tag":"helper","protocol":"socks","listen":"127.0.0.1","port":10810}]"""))
        val runtime=CustomXrayConfig.prepare(source.toString(),false)
        val selected=org.json.JSONArray(CustomXrayConfig.trafficInboundTags(runtime,false))
        assertEquals(2,selected.length())
        assertEquals(setOf("nirang-custom-socks","nirang-custom-http"),(0 until selected.length()).map {selected.getString(it)}.toSet())
    }
    @Test fun `proxy entrance loopback reentry is unavailable instead of reporting a duplicated lower bound`() {
        for (address in listOf("127.0.0.1","::1","localhost")) {
            val source=JSONObject(raw).put("outbounds",org.json.JSONArray().put(JSONObject()
                .put("tag","user-chain").put("protocol","socks").put("settings",JSONObject().put("servers",org.json.JSONArray()
                    .put(JSONObject().put("address",address).put("port",10809))))))
            val proxyRuntime=CustomXrayConfig.prepare(source.toString(),false)
            assertNull(CustomXrayConfig.trafficInboundTags(proxyRuntime,false))
            // The same topology still has a single real ingress in VPN mode.
            val vpnRuntime=CustomXrayConfig.prepare(source.toString(),true)
            assertEquals(1,org.json.JSONArray(CustomXrayConfig.trafficInboundTags(vpnRuntime,true)).length())
        }
        val auxiliary=JSONObject(raw).put("outbounds",org.json.JSONArray("""[{"tag":"chain","protocol":"socks","settings":{"servers":[{"address":"127.0.0.1","port":10810}]}}]"""))
        assertNotNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(auxiliary.toString(),false),false))
    }
    @Test fun `native-compatible null telemetry objects are supplied without blocking the profile`() {
        for (policy in listOf(JSONObject.NULL,JSONObject().put("system",JSONObject.NULL))) {
            val source=JSONObject(raw).put("stats",JSONObject.NULL).put("policy",policy)
            val result=JSONObject(CustomXrayConfig.prepare(source.toString(),true))
            assertTrue(result.getJSONObject("policy").getJSONObject("system").getBoolean("statsInboundUplink"))
            assertNotNull(result.getJSONObject("stats"))
        }
    }
    @Test fun `freedom redirect back to owned proxy entrances cannot be double-counted`() {
        for (redirect in listOf("127.0.0.1:10809","[::1]:10808","localhost:10809")) {
            val source=JSONObject(raw).put("outbounds",org.json.JSONArray().put(JSONObject().put("tag","user-redirect")
                .put("protocol","freedom").put("settings",JSONObject().put("redirect",redirect))))
            assertNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(source.toString(),false),false))
            assertNotNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(source.toString(),true),true))
        }
        val source=JSONObject(raw).put("outbounds",org.json.JSONArray("""[{"tag":"user-redirect","protocol":"freedom","settings":{"redirect":"127.0.0.1:10810"}}]"""))
        assertNotNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(source.toString(),false),false))
    }
    @Test fun `known DNS hosts aliases into owned proxy entrances are unavailable without rewriting DNS`() {
        for (hosts in listOf(
            """{"relay.test":"127.0.0.1"}""",
            """{"full:relay.test":["::1"]}""",
            """{"domain:test":"relay.internal","relay.internal":"127.0.0.1"}"""
        )) {
            val source=JSONObject(raw).put("dns",JSONObject().put("hosts",JSONObject(hosts)))
                .put("outbounds",org.json.JSONArray("""[{"tag":"user-relay","protocol":"socks","settings":{"servers":[{"address":"relay.test","port":10808}]}}]"""))
            val runtime=CustomXrayConfig.prepare(source.toString(),false)
            assertNull(CustomXrayConfig.trafficInboundTags(runtime,false))
            assertEquals(source.getJSONObject("dns").toString(),JSONObject(runtime).getJSONObject("dns").toString())
            assertNotNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(source.toString(),true),true))
        }
        val public=JSONObject(raw).put("dns",JSONObject().put("hosts",JSONObject("""{"relay.test":"192.0.2.1"}""")))
            .put("outbounds",org.json.JSONArray("""[{"tag":"user-relay","protocol":"socks","settings":{"servers":[{"address":"relay.test","port":10808}]}}]"""))
        assertNotNull(CustomXrayConfig.trafficInboundTags(CustomXrayConfig.prepare(public.toString(),false),false))
    }
    @Test fun `unsafe listener local file and control service never pass through`() {
        for (extra in listOf(
            "\"inbounds\":[{\"protocol\":\"socks\",\"listen\":\"0.0.0.0\",\"port\":1080}]",
            "\"log\":{\"access\":\"/data/private/file\"}",
            "\"api\":{\"services\":[\"HandlerService\"]}",
            "\"extra\":{\"certificateFile\":\"/private/token\"}"
        )) {
            val value = raw.dropLast(1)+","+extra+"}"
            try { CustomXrayConfig.prepare(value,true);fail("Unsafe custom config accepted") }
            catch (_:IllegalArgumentException) { }
        }
    }
    @Test fun `existing compatible loopback inputs are reused without duplication`() {
        val value = JSONObject(raw).put("inbounds", org.json.JSONArray("""[{"protocol":"socks","listen":"127.0.0.1","port":10808,"settings":{"auth":"noauth"}},{"protocol":"http","listen":"127.0.0.1","port":10809}]"""))
        assertEquals(3,JSONObject(CustomXrayConfig.prepare(value.toString(),true)).getJSONArray("inbounds").length())
    }
}
