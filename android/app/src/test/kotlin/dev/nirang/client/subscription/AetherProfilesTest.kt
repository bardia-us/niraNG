package dev.nirang.client.subscription

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AetherProfilesTest {
    @Test fun `safe route metadata describes topology without identity data`() {
        val profile=AetherProfiles.fromUri("aether://?protocol=mim&psiphon=reverse")
        val record=dev.nirang.client.model.ServerRecord("local",profile.name,"","custom","",0,"","json","custom",emptyMap(),customProfile=profile,origin="local")
        val metadata=record.safeMetadata(record.id)
        assertEquals("masque-in-masque",metadata["aetherMode"])
        assertEquals("reverse",metadata["psiphonPlacement"])
        assertFalse(metadata.containsKey("payload"))
        assertFalse(metadata.containsKey("privateKey"))
    }
    @Test fun `editor values keep nested history message-codec safe`() {
        val values=AetherProfiles.editorValues("""{"endpointHistory":{"masque":{"endpoint":"162.159.199.65:443"}}}""")
        val history=values["endpointHistory"] as Map<*,*>
        assertEquals("162.159.199.65:443", (history["masque"] as Map<*,*>)["endpoint"])
    }
    private val link = "aether://?protocol=wg-over-masque&scan=balanced&ip=v4&transport=h2&outer=162.159.199.65%3A443&psiphon=chain&psiphon_mode=auto#test"
    @Test fun `owner URI maps real typed options without changing endpoint`() {
        val p = AetherProfiles.fromUri(link,"local_test","My Aether")
        val json = JSONObject(p.payload)
        assertEquals("wireguard-over-masque",json.getString("mode"))
        assertEquals("h2",json.getString("carrier"))
        assertEquals("162.159.199.65:443",json.getString("outerEndpoint"))
        assertEquals("auto",json.getString("psiphonMode"))
        assertEquals("My Aether",p.name)
    }
    @Test fun `defaults prefer Psiphon and also include a direct Aether profile`() {
        val defaults=AetherProfiles.defaults()
        assertEquals(3,defaults.size)
        assertEquals("chain",JSONObject(defaults.first().payload).getString("psiphon"))
        assertEquals("off",JSONObject(defaults.last().payload).getString("psiphon"))
        assertTrue(defaults.all { it.name != "test" })
        assertEquals("WireGuard | Irancell", defaults.last().name)
        assertEquals("wireguard", JSONObject(defaults.last().payload).getString("mode"))
        assertEquals(3,defaults.map { it.id }.toSet().size)
    }
    @Test fun `unknown repeated and unsafe URI options are refused`() {
        for (bad in listOf(link.replace("scan=balanced","scan=balanced&scan=turbo"),link.replace("ip=v4","ip=v4&api_sni=evil.example"),link.replace("162.159.199.65%3A443","127.0.0.1%3A443"))) {
            try { AetherProfiles.fromUri(bad,"id","test");fail("Invalid Aether URI accepted") }
            catch (_:IllegalArgumentException) { }
        }
    }
}
