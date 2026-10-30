package dev.nirang.client.vpn

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ServerSelectionTest {
    @Test
    fun `rejected native profile never changes selection or queues a disconnect`() {
        var selected="healthy"
        var queued=false
        try {
            ServerSelection.select("bad",true,persist={selected=it},queueSwitch={queued=true},
                validateCandidate={throw IllegalArgumentException("incompatible native config")})
            throw AssertionError("Expected validation rejection")
        } catch (_:IllegalArgumentException) {
            assertEquals("healthy",selected)
            assertFalse(queued)
        }
    }
    @Test
    fun `requested selection is visible before queued core work completes`() {
        var selected = "old"
        var connected = false
        val calls = mutableListOf<String>()
        var completeCore: (() -> Unit)? = null
        ServerSelection.select(
            "new", true,
            persist = { selected = it; calls += "select:$it" },
            queueSwitch = {
                assertEquals("new", selected)
                calls += "queue:$it"
                completeCore = { connected = true }
            },
        )
        assertEquals("new", selected)
        assertEquals(listOf("select:new", "queue:new"), calls)
        assertFalse(connected)
        completeCore!!.invoke()
        assertEquals(true, connected)
    }

    @Test
    fun `disconnected selection does not start the VPN`() {
        var selected = "old"
        ServerSelection.select("new", false,
            persist = { selected = it },
            queueSwitch = { throw AssertionError("must not start a service") },
        )
        assertEquals("new", selected)
    }

    @Test
    fun `failed persistence never queues core work`() {
        var queued = false
        try {
            ServerSelection.select("new", true,
                persist = { throw IllegalStateException("storage unavailable") },
                queueSwitch = { queued = true },
            )
            throw AssertionError("Expected persistence failure")
        } catch (_: IllegalStateException) {
            assertFalse(queued)
        }
    }
}
