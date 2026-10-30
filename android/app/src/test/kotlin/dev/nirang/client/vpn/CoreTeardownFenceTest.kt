package dev.nirang.client.vpn

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicBoolean
import org.junit.Assert.*
import org.junit.Test

class CoreTeardownFenceTest {
    @Test fun `revocation returns immediately and next service startup waits for complete old teardown`() {
        val fence=CoreTeardownFence()
        val closing=CountDownLatch(1);val release=CountDownLatch(1);val started=CountDownLatch(1)
        try {
            fence.schedule { closing.countDown();release.await() }
            assertTrue(closing.await(2,TimeUnit.SECONDS))
            val next=Thread { fence.awaitPreviousStops { true };started.countDown() }.apply { start() }
            assertFalse(started.await(100,TimeUnit.MILLISECONDS))
            release.countDown()
            assertTrue(started.await(2,TimeUnit.SECONDS))
            next.join(2000)
        } finally { release.countDown();fence.shutdown() }
    }

    @Test fun `cancelled replacement does not wait for unresponsive native close`() {
        val fence=CoreTeardownFence()
        val closing=CountDownLatch(1);val release=CountDownLatch(1);val cancelled=CountDownLatch(1)
        val current=AtomicBoolean(true)
        try {
            fence.schedule { closing.countDown();release.await() }
            assertTrue(closing.await(2,TimeUnit.SECONDS))
            val next=Thread { try { fence.awaitPreviousStops(current::get);fail("Cancelled startup claimed resources") }
                catch (_:CancellationException) { cancelled.countDown() } }.apply { start() }
            current.set(false)
            assertTrue(cancelled.await(2,TimeUnit.SECONDS))
            next.join(2000)
        } finally { release.countDown();fence.shutdown() }
    }
}
