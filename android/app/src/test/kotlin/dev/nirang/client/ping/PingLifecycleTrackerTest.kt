package dev.nirang.client.ping

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PingLifecycleTrackerTest {
    @Test
    fun `cancel releases every row from testing state`() {
        val tracker = PingLifecycleTracker()
        tracker.start("one")
        tracker.start("two")

        assertEquals(setOf("one", "two"), tracker.cancelAll().toSet())
        assertTrue(tracker.cancelAll().isEmpty())
    }

    @Test
    fun `completed row is not reset by a later cancellation`() {
        val tracker = PingLifecycleTracker()
        tracker.start("done")
        tracker.start("pending")
        tracker.finish("done")

        assertEquals(listOf("pending"), tracker.cancelAll())
    }
}
