package dev.nirang.client.cores.singbox

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class SingBoxLifecycleTest {
    private class Resource : AutoCloseable { val closes = AtomicInteger(); override fun close() { closes.incrementAndGet() } }

    @Test fun failureClosesPartiallyStartedResource() {
        val lifecycle = SingBoxLifecycle<Resource>()
        val resource = Resource()
        assertThrows(IllegalStateException::class.java) { lifecycle.start({ resource }, { error("native start failed") }) }
        assertEquals(1, resource.closes.get())
        assertFalse(lifecycle.isRunning)
    }

    @Test fun runningStateAndRepeatedStopReflectActualLifecycle() {
        val lifecycle = SingBoxLifecycle<Resource>()
        val resource = Resource()
        lifecycle.start({ resource }, {})
        assertTrue(lifecycle.isRunning)
        lifecycle.stop()
        lifecycle.stop()
        assertFalse(lifecycle.isRunning)
        assertEquals(1, resource.closes.get())
    }

    @Test fun stopInvalidatesInFlightStartAndClosesOnce() {
        val lifecycle = SingBoxLifecycle<Resource>()
        val entered = CountDownLatch(1)
        val proceed = CountDownLatch(1)
        val resource = Resource()
        val failure = AtomicReference<Throwable?>()
        val starter = Thread {
            try { lifecycle.start({ resource }) { entered.countDown(); check(proceed.await(3, TimeUnit.SECONDS)) } }
            catch (error: Throwable) { failure.set(error) }
        }
        starter.start()
        assertTrue(entered.await(3, TimeUnit.SECONDS))
        val stopper = Thread { lifecycle.stop() }
        stopper.start()
        // Wait for stop's cancellation signal without relying on thread scheduling.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
        while (stopper.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.yield()
        assertEquals(Thread.State.BLOCKED, stopper.state)
        proceed.countDown()
        starter.join(3000); stopper.join(3000)
        assertNotNull(failure.get())
        assertFalse(lifecycle.isRunning)
        assertEquals(1, resource.closes.get())
    }
}
