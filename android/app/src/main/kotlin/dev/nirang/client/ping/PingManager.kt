package dev.nirang.client.ping

import android.content.Context
import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ServerEligibility
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.xray.XrayConfigBuilder
import dev.nirang.client.xray.XrayCore
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class PingManager(
    private val context: Context,
    private val repository: SubscriptionRepository,
) {
    private val executor = Executors.newFixedThreadPool(MAX_CONCURRENCY)
    private val probeExecutor = Executors.newFixedThreadPool(MAX_CONCURRENCY)
    private val generation = AtomicInteger(0)
    private val pending = AtomicInteger(0)
    private val tasks = mutableListOf<Future<*>>()
    private val lifecycle = PingLifecycleTracker()
    // Separate service auto-probes and manual probes, including overlapping
    // probes of the same server across reconnects.
    private val managerId = java.util.UUID.randomUUID().toString()

    fun testSingle(serverId: String, awaitReady: Boolean = false, onComplete: (() -> Unit)? = null) {
        cancelTasks(emitEvent = false)
        val currentGeneration = generation.get()
        pending.set(1)
        repository.updatePing(serverId, null, "testing")
        lifecycle.start(serverId)
        emit(serverId, null, "testing")
        val limiter = Semaphore(1)
        synchronized(tasks) { tasks += executor.submit { test(serverId, currentGeneration, limiter, false, onComplete, awaitReady) } }
    }

    fun testAll() {
        cancelTasks(emitEvent = false)
        val currentGeneration = generation.get()
        val ids = repository.visibleServerIds().sortedBy { if(repository.server(it)?.customProfile?.kind == "aether") 1 else 0 }
        val limiter = Semaphore(NativeSettings(context).realPingConcurrency)
        pending.set(ids.size)
        if (ids.isEmpty()) NativeEvents.emit("pingCompleted", null)
        ids.forEach { serverId ->
            repository.updatePing(serverId, null, "testing")
            lifecycle.start(serverId)
            emit(serverId, null, "testing")
            synchronized(tasks) { tasks += executor.submit { test(serverId, currentGeneration, limiter, false, null) } }
        }
    }

    fun testAllTcp() {
        cancelTasks(emitEvent = false)
        val currentGeneration = generation.get()
        val ids = repository.visibleServerIds().sortedBy { if(repository.server(it)?.customProfile?.kind == "aether") 1 else 0 }
        val limiter = Semaphore(NativeSettings(context).realPingConcurrency)
        pending.set(ids.size)
        if (ids.isEmpty()) NativeEvents.emit("pingCompleted", null)
        ids.forEach { serverId ->
            repository.updatePing(serverId, null, "testing")
            lifecycle.start(serverId)
            emit(serverId, null, "testing")
            synchronized(tasks) { tasks += executor.submit { test(serverId, currentGeneration, limiter, true, null) } }
        }
    }

    fun cancel() {
        cancelTasks(emitEvent = true)
    }

    fun close() {
        cancelTasks(emitEvent = false)
        executor.shutdownNow()
        probeExecutor.shutdownNow()
    }

    private fun cancelTasks(emitEvent: Boolean) {
        generation.incrementAndGet()
        pending.set(0)
        synchronized(tasks) {
            tasks.forEach { it.cancel(true) }
            tasks.clear()
        }
        lifecycle.cancelAll().forEach { serverId ->
            repository.updatePing(serverId, null, "idle")
            emit(serverId, null, "idle")
        }
        if (emitEvent) NativeEvents.emit("pingCancelled", null)
    }

    private fun test(
        serverId: String,
        expectedGeneration: Int,
        limiter: Semaphore,
        tcpOnly: Boolean,
        onComplete: (() -> Unit)?,
        awaitReady: Boolean = false,
    ) {
        var acquired = false
        try {
            limiter.acquire()
            acquired = true
            if (generation.get() != expectedGeneration || Thread.currentThread().isInterrupted) return
            val server = repository.server(serverId) ?: return
            // Full profiles have no single TCP endpoint. Their real-delay path below
            // starts an independent native session with private loopback listeners.
            if (tcpOnly && server.customProfile != null) {
                repository.updatePing(serverId, null, "unavailable")
                emit(serverId, null, "unavailable")
                lifecycle.finish(serverId)
                return
            }
            if (ServerEligibility.rejectionReason(server) != null) {
                repository.updatePing(serverId, null, "failed")
                emit(serverId, null, "failed")
                lifecycle.finish(serverId)
                return
            }
            // Reuse the running Aether/Psiphon chain. A second cold core measures
            // another tunnel and its bootstrap, not the connection shown on Home.
            val active = dev.nirang.client.vpn.NirangVpnService.diagnosticTarget()
                ?.takeIf { it.first == serverId && it.second.engine == "aether" }
                ?.second
            val delay = runCatching {
                val cancellation = ProbeCancellation(dev.nirang.client.vpn.AsyncNativeStop::execute)
                val started = java.util.concurrent.CountDownLatch(if(server.customProfile != null && active == null) 1 else 0)
                val probe = probeExecutor.submit<Long> {
                    try {
                    if (active != null) {
                        measureActive(active, cancellation, awaitReady)
                    } else if (server.customProfile != null) {
                        CustomProfileLatencyProbe.measure(context,server.customProfile,TEST_URL,cancellation) { started.countDown() }
                    } else if (tcpOnly) {
                        TcpLatencyProbe.measure(server.address, server.port)
                    } else {
                        val config = XrayConfigBuilder.buildProbeConfig(server, NativeSettings(context))
                        XrayCore.measureOutboundDelay(config, TEST_URL)
                    }
                    } finally { started.countDown() }
                }
                try {
                    // Waiting for the global native memory budget is queue time,
                    // not a failed network measurement. Cancellation interrupts this wait.
                    started.await()
                    probe.get(if(server.customProfile?.engine == "aether") AETHER_TIMEOUT_SECONDS else PING_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                } finally {
                    cancellation.cancel()
                    if (!probe.isDone) probe.cancel(true)
                }
            }.getOrDefault(-1L)
            if (generation.get() != expectedGeneration || Thread.currentThread().isInterrupted) return
            if (active != null && !active.diagnosticCurrent()) {
                lifecycle.finish(serverId)
                return
            }
            val status = if (delay >= 0) "success" else "timeout"
            repository.updatePing(serverId, delay.takeIf { it >= 0 }, status)
            emit(serverId, delay.takeIf { it >= 0 }, status, expectedGeneration)
            lifecycle.finish(serverId)
            SafeLog.info(context, if (tcpOnly) "TCP delay completed" else "Real delay completed")
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        } finally {
            if (acquired) limiter.release()
            if (generation.get() == expectedGeneration && pending.decrementAndGet() == 0) {
                NativeEvents.emit("pingCompleted", null)
            }
            onComplete?.invoke()
        }
    }

    private fun measureActive(
        core: dev.nirang.client.vpn.ConnectionCore,
        cancellation: ProbeCancellation,
        awaitReady: Boolean,
    ): Long {
        // A local SOCKS listener can be ready before Psiphon has its first tunnel.
        // Retry readiness only for the automatic post-connect measurement.
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(if (awaitReady) 30 else 6)
        while (true) {
            cancellation.check()
            check(core.diagnosticCurrent()) { "Connection changed" }
            val remaining = TimeUnit.NANOSECONDS.toMillis(deadline - System.nanoTime()).toInt()
            if (remaining <= 0) return -1L
            try {
                val port = core.diagnosticSocksPort() ?: return -1L
                return SocksHttpLatencyProbe.measure(port, TEST_URL, cancellation, minOf(remaining, 4000))
            } catch (_: java.io.IOException) {
                cancellation.check()
                if (!awaitReady || System.nanoTime() >= deadline) return -1L
                Thread.sleep(300)
            }
        }
    }

    private fun emit(serverId: String, ping: Long?, status: String, probeGeneration: Int = generation.get()) {
        NativeEvents.emit("serverPing", mapOf(
            "id" to serverId, "ping" to ping, "status" to status,
            "probeId" to "$managerId:$probeGeneration:$serverId",
        ))
    }

    companion object {
        private const val MAX_CONCURRENCY = 32
        private const val PING_TIMEOUT_SECONDS = 5L
        private const val AETHER_TIMEOUT_SECONDS = 45L
        private const val TEST_URL = "https://www.google.com/generate_204"
    }
}
