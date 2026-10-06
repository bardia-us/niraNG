package dev.nirang.client.registration

import org.junit.Assert.assertEquals
import org.junit.Test
import java.net.SocketTimeoutException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse

class ApiRequestDeadlineTest {
    private class Connection : HttpURLConnection(URL("https://example.invalid")) {
        val disconnected = CountDownLatch(1)
        override fun disconnect() { disconnected.countDown() }
        override fun usingProxy() = false
        override fun connect() {}
    }

    @Test fun `stalled connection is actively disconnected on deadline`() {
        val connection = Connection()
        ApiRequestDeadline(20).watch(connection).use {
            assertTrue(connection.disconnected.await(500, TimeUnit.MILLISECONDS))
        }
    }

    @Test fun `completed request cancels its disconnect watchdog`() {
        val connection = Connection()
        ApiRequestDeadline(30).watch(connection).close()
        assertFalse(connection.disconnected.await(80, TimeUnit.MILLISECONDS))
    }

    @Test fun `submillisecond remainder never becomes an infinite zero timeout`() {
        var now = 0L
        val deadline = ApiRequestDeadline(1) { now }
        now = 999_999L
        assertEquals(1, deadline.remainingMillis())
    }
    @Test fun `token retry receives remaining budget not another seven seconds`() {
        var now = 0L
        val deadline = ApiRequestDeadline(7_000) { now }
        assertEquals(7_000, deadline.remainingMillis())
        now = 6_900_000_000L
        assertEquals(100, deadline.remainingMillis())
    }

    @Test(expected = SocketTimeoutException::class)
    fun `expired budget cannot open another API connection`() {
        var now = 0L
        val deadline = ApiRequestDeadline(7_000) { now }
        now = 7_000_000_000L
        deadline.remainingMillis()
    }
}
