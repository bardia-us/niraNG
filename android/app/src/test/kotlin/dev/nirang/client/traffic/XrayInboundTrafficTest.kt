package dev.nirang.client.traffic

import org.junit.Assert.*
import org.junit.Test
import java.time.Instant
import java.util.TimeZone

class XrayInboundTrafficTest {
    @Test fun `inbound cumulative bytes are counted once across repeat samples and final drain`() {
        val session = XrayInboundTraffic()
        assertEquals("proxy,uplink,101;proxy,downlink,200",session.sample("""{"uplink":101,"downlink":200}"""))
        assertEquals("proxy,uplink,0;proxy,downlink,0",session.sample("""{"uplink":101,"downlink":200}"""))
        assertEquals("proxy,uplink,10;proxy,downlink,23",session.sample("""{"uplink":111,"downlink":223}"""))
        // A new controller session starts from zero, rather than subtracting the
        // previous controller's counters after reconnect.
        assertEquals("proxy,uplink,7;proxy,downlink,8",XrayInboundTraffic().sample("""{"uplink":7,"downlink":8}"""))
    }

    @Test fun `failed reads retain the last valid baseline so recovery loses no bytes`() {
        val session = XrayInboundTraffic()
        session.sample("""{"uplink":100,"downlink":200}""")
        for (raw in listOf(null,"", "{}", """{"uplink":"100","downlink":200}""", """{"uplink":100.5,"downlink":200}""", """{"uplink":-1,"downlink":200}""", """{"uplink":9223372036854775808,"downlink":200}""")) {
            assertNull(session.sample(raw))
        }
        assertEquals("proxy,uplink,12;proxy,downlink,34",session.sample("""{"uplink":112,"downlink":234}"""))
    }

    @Test fun `counter reset cannot become a huge delta or a fabricated exact zero`() {
        val session=XrayInboundTraffic()
        session.sample("""{"uplink":100,"downlink":200}""")
        assertNull(session.sample("""{"uplink":2,"downlink":3}"""))
        assertEquals("proxy,uplink,3;proxy,downlink,4",session.sample("""{"uplink":5,"downlink":7}"""))
    }

    @Test fun `custom final drains and reconnects add to existing history without clearing partial coverage`() {
        val zone=TimeZone.getTimeZone("UTC")
        val now=Instant.parse("2026-10-30T12:00:00Z").toEpochMilli()
        val original=MeasuredTrafficLedger(null,now,zone)
        original.begin(now,zone)
        original.record("proxy,downlink,50",now+1,zone)
        original.end(now+1,zone)
        val ledger=MeasuredTrafficLedger(original.encode(),now+2,zone)
        val session=XrayInboundTraffic()
        ledger.begin(now+2,zone)
        ledger.record(session.sample("""{"uplink":101,"downlink":200}"""),now+3,zone)
        ledger.record(session.sample("""{"uplink":101,"downlink":200}"""),now+4,zone)
        ledger.record(session.sample(null),now+5,zone)
        ledger.record(session.sample("""{"uplink":111,"downlink":223}"""),now+6,zone)
        ledger.end(now+6,zone)
        ledger.begin(now+7,zone)
        ledger.record(XrayInboundTraffic().sample("""{"uplink":7,"downlink":8}"""),now+8,zone)
        ledger.end(now+8,zone)
        val snapshot=ledger.snapshot(now+9,zone)
        assertEquals(399L,snapshot["todayBytes"])
        assertEquals(399L,snapshot["monthBytes"])
        assertEquals(true,snapshot["todayPartial"])
        assertEquals(true,snapshot["monthPartial"])
        assertEquals(true,snapshot["available"])
    }
}
