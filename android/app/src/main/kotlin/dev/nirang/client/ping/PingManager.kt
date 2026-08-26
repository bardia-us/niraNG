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

    fun testSingle(serverId: String) {
        cancelTasks(emitEvent = false)
        val currentGeneration = generation.get()
        pending.set(1)
        repository.updatePing(serverId, null, "testing")
        emit(serverId, null, "testing")
        val limiter = Semaphore(1)
        synchronized(tasks) { tasks += executor.submit { test(serverId, currentGeneration, limiter) } }
    }

    fun testAll() {
        cancelTasks(emitEvent = false)
        val currentGeneration = generation.get()
        val ids = repository.visibleServerIds()
        val limiter = Semaphore(NativeSettings(context).realPingConcurrency)
        pending.set(ids.size)
        if (ids.isEmpty()) NativeEvents.emit("pingCompleted", null)
        ids.forEach { serverId ->
            repository.updatePing(serverId, null, "testing")
            emit(serverId, null, "testing")
            synchronized(tasks) { tasks += executor.submit { test(serverId, currentGeneration, limiter) } }
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
        if (emitEvent) NativeEvents.emit("pingCancelled", null)
    }

    private fun test(serverId: String, expectedGeneration: Int, limiter: Semaphore) {
        var acquired = false
        try {
            limiter.acquire()
            acquired = true
            if (generation.get() != expectedGeneration || Thread.currentThread().isInterrupted) return
            val server = repository.server(serverId) ?: return
            if (ServerEligibility.rejectionReason(server) != null) {
                repository.updatePing(serverId, null, "failed")
                emit(serverId, null, "failed")
                return
            }
            val delay = runCatching {
                val config = XrayConfigBuilder.buildProbeConfig(server, NativeSettings(context))
                val probe = probeExecutor.submit<Long> {
                    XrayCore.measureOutboundDelay(config, TEST_URL)
                }
                try {
                    probe.get(PING_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                } finally {
                    if (!probe.isDone) probe.cancel(true)
                }
            }.getOrDefault(-1L)
            if (generation.get() != expectedGeneration || Thread.currentThread().isInterrupted) return
            val status = if (delay >= 0) "success" else "timeout"
            repository.updatePing(serverId, delay.takeIf { it >= 0 }, status)
            emit(serverId, delay.takeIf { it >= 0 }, status)
            SafeLog.info(context, "Ping completed")
        } finally {
            if (acquired) limiter.release()
            if (generation.get() == expectedGeneration && pending.decrementAndGet() == 0) {
                NativeEvents.emit("pingCompleted", null)
            }
        }
    }

    private fun emit(serverId: String, ping: Long?, status: String) {
        NativeEvents.emit("serverPing", mapOf("id" to serverId, "ping" to ping, "status" to status))
    }

    companion object {
        private const val MAX_CONCURRENCY = 32
        private const val PING_TIMEOUT_SECONDS = 6L
        private const val TEST_URL = "https://www.google.com/generate_204"
    }
}
