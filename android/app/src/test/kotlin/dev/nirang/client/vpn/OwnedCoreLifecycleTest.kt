package dev.nirang.client.vpn

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

class OwnedCoreLifecycleTest {
    @Test fun `revocation publishes stopped without waiting for native close`() {
        val lifecycle = OwnedCoreLifecycle()
        val owner = Any()
        val closing = CountDownLatch(1)
        val release = CountDownLatch(1)
        lifecycle.start(owner) {}
        val thread = Thread { lifecycle.stop(owner) { closing.countDown(); release.await() } }.apply { start() }
        try {
            assertTrue(closing.await(2, TimeUnit.SECONDS))
            assertFalse(lifecycle.isRunning)
        } finally { release.countDown(); thread.join(2000) }
    }

    @Test fun `duplicate delayed stop does not stop a later session`() {
        val lifecycle = OwnedCoreLifecycle()
        val first = Any(); val next = Any()
        lifecycle.start(first) {}
        lifecycle.stop(first) {}
        lifecycle.start(next) {}
        lifecycle.stop(first) { fail("Stale stop reached native core") }
        assertTrue(lifecycle.isRunning)
        lifecycle.stop(next) {}
    }

    @Test fun `failed start never publishes a running owner`() {
        val lifecycle = OwnedCoreLifecycle()
        assertThrows(IllegalStateException::class.java) { lifecycle.start(Any()) { error("Native start failed") } }
        assertFalse(lifecycle.isRunning)
        lifecycle.start(Any()) {}
        assertTrue(lifecycle.isRunning)
    }

    @Test fun `late cancelled start cannot revive core after its stop already completed`() {
        val lifecycle=OwnedCoreLifecycle()
        val owner=Any()
        lifecycle.stop(owner) {}
        assertThrows(java.util.concurrent.CancellationException::class.java) {
            lifecycle.start(owner,current={false}) { fail("Late startup reached native core") }
        }
        assertFalse(lifecycle.isRunning)
    }

    @Test fun `new start waits until old native close finishes`() {
        val lifecycle = OwnedCoreLifecycle()
        val first = Any(); val next = Any()
        val closing = CountDownLatch(1); val release = CountDownLatch(1); val started = CountDownLatch(1)
        lifecycle.start(first) {}
        val stop = Thread { lifecycle.stop(first) { closing.countDown(); release.await() } }.apply { start() }
        assertTrue(closing.await(2, TimeUnit.SECONDS))
        val start = Thread { lifecycle.start(next) { started.countDown() } }.apply { start() }
        try { assertFalse(started.await(100, TimeUnit.MILLISECONDS)) }
        finally { release.countDown(); stop.join(2000); start.join(2000) }
        assertTrue(lifecycle.isRunning)
    }
}
