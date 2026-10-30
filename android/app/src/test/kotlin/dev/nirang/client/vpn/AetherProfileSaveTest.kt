package dev.nirang.client.vpn

import org.junit.Assert.*
import org.junit.Test

class AetherProfileSaveTest {
    private class Fixture {
        var payload = """{"psiphon":"only","psiphonRegion":"US"}"""
        var active: String? = "local_aether_one"
        var running = true
        var saves = 0
        val restarts = mutableListOf<Pair<String,String>>()
        fun save(id: String? = "local_aether_one", next: String = payload): List<String> = AetherProfileSave.save(
            id, { payload }, { saves++;payload = next;listOf("same result") },
            { active }, { running }, { restarts += it to payload },
        )
    }

    @Test fun `changed region persists before restarting real active profile and keeps result`() {
        val fixture = Fixture()
        assertEquals(listOf("same result"), fixture.save(next="""{"psiphon":"only","psiphonRegion":"JP"}"""))
        assertEquals(1, fixture.saves)
        assertEquals(listOf("local_aether_one" to """{"psiphon":"only","psiphonRegion":"JP"}"""), fixture.restarts)
    }

    @Test fun `creating inactive editing and disconnected editing never restart another connection`() {
        for (mode in 0..2) {
            val fixture = Fixture()
            if (mode == 1) fixture.active = "real_other_profile"
            if (mode == 2) fixture.running = false
            fixture.save(id=if (mode == 0) null else "local_aether_one", next="""{"psiphon":"only","psiphonRegion":"ZA"}""")
            assertEquals(1,fixture.saves)
            assertTrue(fixture.restarts.isEmpty())
        }
    }

    @Test fun `rename no-op reordered keys and explicit default do not restart`() {
        val fixture = Fixture()
        fixture.save()
        fixture.save(next="""{"psiphonRegion":"US","psiphon":"only","keepalive":5}""")
        assertEquals(2,fixture.saves)
        assertTrue(fixture.restarts.isEmpty())
    }

    @Test fun `failed persistence never restarts or returns success`() {
        val fixture = Fixture()
        try {
            AetherProfileSave.save("local_aether_one", { fixture.payload }, { error("disk failure") },
                { fixture.active }, { true }, { fixture.restarts += it to fixture.payload })
            fail("Failed save was accepted")
        } catch (_:IllegalStateException) { }
        assertTrue(fixture.restarts.isEmpty())
    }

    @Test fun `every effective connection option change restarts active profile`() {
        val changes = listOf(
            """{"mode":"wireguard","psiphon":"only","psiphonRegion":"US"}""",
            """{"psiphon":"chain","psiphonRegion":"US"}""",
            """{"psiphon":"only","psiphonRegion":"US","psiphonMode":"cdn"}""",
            """{"psiphon":"only","psiphonRegion":"US","scan":"stealth"}""",
            """{"psiphon":"only","psiphonRegion":"US","carrier":"h2"}""",
            """{"psiphon":"only","psiphonRegion":"US","ipFamily":"v6"}""",
            """{"psiphon":"only","psiphonRegion":"US","endpoint":"162.159.199.65:443"}""",
            """{"psiphon":"only","psiphonRegion":"US","keepalive":10}""",
            """{"psiphon":"only","psiphonRegion":"US","dns":"1.0.0.1"}""",
            """{"psiphon":"only","psiphonRegion":"US","startupTimeoutSeconds":30}""",
        )
        for (change in changes) {
            val fixture = Fixture()
            fixture.save(next=change)
            assertEquals(1, fixture.restarts.size)
        }
    }

    @Test fun `stop arriving during save prevents automatic reconnect`() {
        val fixture = Fixture()
        AetherProfileSave.save("local_aether_one", { fixture.payload }, {
            fixture.active = null;fixture.running = false
            fixture.payload = """{"psiphon":"only","psiphonRegion":"JP"}"""
        }, { fixture.active }, { fixture.running }, { fixture.restarts += it to fixture.payload })
        assertTrue(fixture.restarts.isEmpty())
    }
}
