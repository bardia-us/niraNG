package dev.nirang.client.vpn

import org.junit.Assert.*
import org.junit.Test

class CoreTrafficDeltaTest {
    @Test fun `cumulative counters are converted once not added on every poll`() {
        val delta=CoreTrafficDelta()
        assertEquals("proxy,uplink,10;proxy,downlink,4",delta.sample(10,4))
        assertEquals("proxy,uplink,2;proxy,downlink,6",delta.sample(12,10))
        assertEquals("proxy,uplink,0;proxy,downlink,0",delta.sample(12,10))
    }
    @Test fun `counter reset is unavailable rather than negative or huge traffic`() {
        val delta=CoreTrafficDelta()
        delta.sample(100,100)
        assertNull(delta.sample(3,4))
        assertEquals("proxy,uplink,2;proxy,downlink,3",delta.sample(5,7))
        assertNull(delta.sample(-1,9))
    }
}
