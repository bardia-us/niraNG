package dev.nirang.client.traffic

import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Test

class MeasuredTrafficLedgerTest {
    private val zone = TimeZone.getTimeZone("Asia/Tehran")
    private fun time(value: String): Long = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)
        .apply { timeZone = zone }.parse(value)!!.time

    @Test fun `unknown before first core session is not zero`() {
        val ledger = MeasuredTrafficLedger(null, time("2026-10-18 12:00:00"), zone)
        assertNull(ledger.snapshot(time("2026-10-18 12:00:00"), zone)["todayBytes"])
    }

    @Test fun `reset deltas accumulate across sessions and persisted app restart`() {
        val now = time("2026-10-18 12:00:00")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record("proxy,uplink,100;proxy,downlink,200;direct,uplink,40;dns-out,uplink,9;blocked,downlink,50;", now + 5000, zone)
        ledger.end(now + 5000, zone)
        val restored = MeasuredTrafficLedger(ledger.encode(), now + 6000, zone)
        restored.begin(now + 6000, zone)
        restored.record("proxy,downlink,60;", now + 11000, zone)
        val snapshot = restored.snapshot(now + 11000, zone)
        assertEquals(400L, snapshot["todayBytes"])
        assertEquals(400L, snapshot["monthBytes"])
        assertEquals(true, snapshot["todayPartial"])
    }

    @Test fun `midnight interval is not guessed but remains in the correct month`() {
        val start = time("2026-10-18 23:59:58")
        val ledger = MeasuredTrafficLedger(null, start, zone)
        ledger.begin(start, zone)
        ledger.record("proxy,downlink,100;", start + 5000, zone)
        ledger.record("proxy,downlink,25;", start + 10000, zone)
        val snapshot = ledger.snapshot(start + 10000, zone)
        assertEquals(25L, snapshot["todayBytes"])
        assertEquals(125L, snapshot["monthBytes"])
        assertEquals(true, snapshot["todayPartial"])
    }

    @Test fun `month and year rollover never assigns a straddling delta to the new month`() {
        val start = time("2026-12-31 23:59:58")
        val ledger = MeasuredTrafficLedger(null, start, zone)
        ledger.begin(start, zone)
        ledger.record("proxy,downlink,100;", start + 5000, zone)
        ledger.record("direct,downlink,20;", start + 10000, zone)
        val snapshot = ledger.snapshot(start + 10000, zone)
        assertEquals(20L, snapshot["todayBytes"])
        assertEquals(20L, snapshot["monthBytes"])
        assertEquals("2027-01", snapshot["month"])
        assertEquals(true, snapshot["monthPartial"])
    }

    @Test fun `empty valid delta is idle and malformed or missing counters never fabricate a total`() {
        val now = time("2026-10-18 12:00:00")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record(null, now + 5000, zone)
        assertNull(ledger.snapshot(now + 5000, zone)["todayBytes"])
        ledger.record("", now + 10000, zone)
        assertEquals(0L, ledger.snapshot(now + 10000, zone)["todayBytes"])
        ledger.record("proxy,downlink,10;", now + 15000, zone)
        ledger.record("proxy,uplink,nope;", now + 20000, zone)
        val snapshot = ledger.snapshot(now + 20000, zone)
        assertEquals(10L, snapshot["todayBytes"])
        assertEquals(true, snapshot["todayPartial"])
        assertEquals(false, snapshot["available"])
    }

    @Test fun `abrupt process death retains saved bytes and marks coverage incomplete`() {
        val now = time("2026-10-18 23:59:58")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record("", now + 5000, zone)
        ledger.record("proxy,downlink,50;", now + 10000, zone)
        assertEquals(false, ledger.snapshot(now + 10000, zone)["todayPartial"])
        val restored = MeasuredTrafficLedger(ledger.encode(), now + 15000, zone)
        assertEquals(50L, restored.snapshot(now + 15000, zone)["todayBytes"])
        assertEquals(true, restored.snapshot(now + 15000, zone)["todayPartial"])
    }

    @Test fun `snapshot before the first new-month drain cannot present an exact zero`() {
        val now = time("2026-10-31 23:59:50")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record("proxy,downlink,50;", now + 5000, zone)
        val pending = ledger.snapshot(now + 15000, zone)
        assertEquals(0L, pending["monthBytes"])
        assertEquals(true, pending["monthPartial"])
        ledger.record("proxy,downlink,20;", now + 15000, zone)
        assertEquals(0L, ledger.snapshot(now + 15000, zone)["monthBytes"])
        assertEquals(true, ledger.snapshot(now + 15000, zone)["monthPartial"])
    }

    @Test fun `new inactive day resets day but retains calendar month total`() {
        val now = time("2026-10-18 12:00:00")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record("proxy,downlink,50;", now + 5000, zone)
        ledger.end(now + 5000, zone)
        val tomorrow = ledger.snapshot(time("2026-10-19 10:00:00"), zone)
        assertEquals(0L, tomorrow["todayBytes"])
        assertEquals(false, tomorrow["todayPartial"])
        assertEquals(50L, tomorrow["monthBytes"])
    }

    @Test fun `timezone or backward clock changes preserve measured bytes without pretending full coverage`() {
        val now = time("2026-10-18 12:00:00")
        val ledger = MeasuredTrafficLedger(null, now, zone)
        ledger.begin(now, zone)
        ledger.record("proxy,downlink,50;", now + 5000, zone)
        ledger.record("proxy,downlink,10;", now - 5000, TimeZone.getTimeZone("UTC"))
        val snapshot = ledger.snapshot(now, TimeZone.getTimeZone("UTC"))
        assertEquals(50L, snapshot["todayBytes"])
        assertEquals(true, snapshot["todayPartial"])
    }
}
