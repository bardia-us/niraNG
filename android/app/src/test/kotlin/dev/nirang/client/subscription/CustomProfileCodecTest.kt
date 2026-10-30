package dev.nirang.client.subscription

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject
import java.util.Base64

class CustomProfileCodecTest {
    @Test fun `PHP fixture decodes byte for byte`() {
        val text = javaClass.getResourceAsStream("/mixed-profile-v1.json")!!.bufferedReader(Charsets.UTF_8).use { it.readText() }
        val fixture = JSONObject(text)
        val parsed = CustomProfileCodec.decode(fixture.getString("line"))
        assertEquals(fixture.getJSONObject("record").getString("payload"), parsed.payload)
        assertEquals(fixture.getJSONObject("record").getString("id"), parsed.id)
        assertEquals(fixture.getJSONObject("record").getString("name"), parsed.name)
    }
    private val raw = "{\n  \"outbounds\": [{\"protocol\": \"freedom\", \"tag\": \"خروجی\"}]\n}"
    private fun wire(payload: String = raw, engine: String = "xray", id: String = "profile_1"): String {
        val envelope = JSONObject().put("version", 1).put("id", id).put("name", "تست 🇸🇪")
            .put("kind", "json").put("engine", engine).put("payload", payload)
        return "nira-profile://v1/" + Base64.getUrlEncoder().withoutPadding().encodeToString(envelope.toString().toByteArray())
    }
    @Test fun `mixed subscription preserves JSON original bytes and order without exposing them`() {
        val normal = "vless://00000000-0000-4000-8000-000000000001@example.com:443?security=tls#normal"
        val result = SubscriptionParser.parseDetailed(normal + "\n" + wire())
        assertTrue(result.stats.complete)
        assertEquals(listOf("normal", "تست 🇸🇪"), result.servers.map { it.name })
        val custom = result.servers.last()
        assertEquals("xray", custom.customProfile!!.engine)
        assertEquals(raw, custom.customProfile!!.payload)
        assertFalse(custom.profileEditable)
        assertFalse(custom.safeMetadata(null).toString().contains("freedom"))
        assertEquals(raw, dev.nirang.client.model.ServerRecord.fromPrivateJson(custom.toPrivateJson()).customProfile!!.payload)
    }
    @Test fun `sing-box is identified separately`() {
        val profile = CustomProfileCodec.decode(wire("{\"outbounds\":[{\"type\":\"direct\"}]}", "sing-box"))
        assertEquals("sing-box", profile.engine)
    }
    @Test fun `Aether preset has a typed engine without private key or process options`() {
        val encoded = JSONObject().put("version",1).put("id","aether_1").put("name","اتر")
            .put("kind","aether").put("engine","aether").put("payload","{\"mode\":\"masque\"}")
        val line = "nira-profile://v1/" + Base64.getUrlEncoder().withoutPadding().encodeToString(encoded.toString().toByteArray())
        assertEquals("aether", CustomProfileCodec.decode(line).kind)
        encoded.put("payload", "{\"mode\":\"masque\",\"privateKey\":\"secret\"}")
        reject("nira-profile://v1/"+Base64.getUrlEncoder().withoutPadding().encodeToString(encoded.toString().toByteArray()))
    }
    @Test fun `ambiguous engines and contradictory declarations fail safely`() {
        for (value in listOf(wire(engine="sing-box"), wire("{\"outbounds\":[{\"protocol\":\"freedom\",\"type\":\"direct\"}]}"), wire("{}"))) {
            reject(value)
        }
    }
    @Test fun `duplicate fields lenient JSON and trailing garbage are rejected`() {
        for (payload in listOf("{\"outbounds\":[],\"outbounds\":[{\"protocol\":\"freedom\"}]}", "{outbounds:[{protocol:'freedom'}]}", raw+"x", "{\"outbounds\":[{\"protocol\":\"freedom\",}]}")) reject(wire(payload))
    }
    @Test fun `bounded depth size and unsafe identifiers`() {
        reject(wire(id="../../private"))
        reject(wire("[".repeat(65)+"0"+"]".repeat(65)))
        reject(wire(raw + " ".repeat(262144)))
        reject("nira-profile://v2/AAAA")
        reject("nira-profile://v1/AAAA?url=secret")
    }
    @Test fun `malformed custom entry makes mixed import incomplete`() {
        val result = SubscriptionParser.parseDetailed(wire() + "\n" + wire(engine="unknown"))
        assertFalse(result.stats.complete)
        assertEquals(1, result.stats.failed)
        assertFalse(result.failures.joinToString().contains("freedom"))
        try { result.requireCompleteCustomProfiles(); fail("Partial custom refresh must fail") }
        catch (_: IllegalArgumentException) { }
    }
    @Test fun `conflicting stable custom IDs reject whole custom refresh`() {
        val result = SubscriptionParser.parseDetailed(wire() + "\n" + wire("{\"outbounds\":[{\"protocol\":\"blackhole\"}]}"))
        try { result.requireCompleteCustomProfiles(); fail("Conflicting IDs must not silently drop data") }
        catch (_: IllegalArgumentException) { }
    }
    private fun reject(value: String) {
        try { CustomProfileCodec.decode(value); fail("Expected invalid custom profile to be rejected") }
        catch (expected: IllegalArgumentException) { assertFalse(expected.message.orEmpty().contains("freedom")) }
    }
}
