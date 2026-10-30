package dev.nirang.client.cores.singbox

import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicLong

internal class SingBoxLifecycle<T : AutoCloseable> {
    private val operation = Any()
    private val generation = AtomicLong()
    @Volatile private var active: T? = null
    val isRunning: Boolean get() = active != null

    fun start(create: (() -> Unit) -> T, launch: (T) -> Unit) = synchronized(operation) {
        check(active == null) { "sing-box is already running" }
        val token = generation.incrementAndGet()
        val assertCurrent = {
            if (generation.get() != token) throw CancellationException("sing-box start cancelled")
            Unit
        }
        val session = create(assertCurrent)
        try {
            assertCurrent()
            launch(session)
            assertCurrent()
            active = session
        } catch (failure: Throwable) {
            runCatching { session.close() }
            throw failure
        }
    }

    fun stop() {
        // Invalidate first: OpenTun/protect cannot publish a TUN after a concurrent stop.
        generation.incrementAndGet()
        synchronized(operation) {
            val session = active
            active = null
            session?.close()
        }
    }
}
