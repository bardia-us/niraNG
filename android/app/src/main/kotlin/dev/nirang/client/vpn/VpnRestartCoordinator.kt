package dev.nirang.client.vpn

import android.content.Context
import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.subscription.SubscriptionRepository
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/** Serializes every full service restart. Rapid requests are reduced to the latest target. */
object VpnRestartCoordinator {
    private data class Request(
        val generation: Long,
        val serverId: String,
        val previousServerId: String?,
    )

    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nirang-vpn-restart").apply { isDaemon = true }
    }
    private val generation = AtomicLong(0)
    private val stoppedGeneration = AtomicLong(0)
    private val latest = AtomicReference<Request?>(null)
    private val draining = AtomicBoolean(false)

    fun request(context: Context, serverId: String): Boolean {
        val appContext = context.applicationContext
        val repository = SubscriptionRepository(appContext)
        val target = repository.server(serverId) ?: return false
        val activeId = ConnectionStore.snapshot()["serverId"] as? String
        val request = Request(generation.incrementAndGet(), target.id, activeId)
        latest.set(request)
        ConnectionStore.transition(ConnectionState.RESTARTING, target.id, target.name)
        if (draining.compareAndSet(false, true)) executor.execute { drain(appContext) }
        return true
    }

    internal fun onServiceStopped(generation: Long) {
        stoppedGeneration.accumulateAndGet(generation, ::maxOf)
    }

    private fun drain(context: Context) {
        try {
            while (!Thread.currentThread().isInterrupted) {
                Thread.sleep(COALESCE_DELAY_MS)
                var request = latest.getAndSet(null) ?: break
                val repository = SubscriptionRepository(context)
                var target = repository.server(request.serverId)
                if (target == null) {
                    fail(context, "Selected server is no longer available")
                    NirangVpnService.stopPreservingError(context)
                    continue
                }

                NirangVpnService.stopForRestart(context, request.generation, target.id, target.name)
                if (!waitForStop(request.generation)) {
                    NirangVpnService.stopPreservingError(context)
                    fail(context, "VPN service did not stop in time")
                    continue
                }

                // Requests received while the old TUN was closing supersede the earlier target.
                latest.getAndSet(null)?.let { newer ->
                    request = newer
                    target = repository.server(newer.serverId)
                }
                if (target == null) {
                    fail(context, "Selected server is no longer available")
                    NirangVpnService.stopPreservingError(context)
                    continue
                }
                val selectedTarget = target

                Thread.sleep(RESTART_DELAY_MS)
                repository.select(selectedTarget.id)
                NativeEvents.emit("servers", repository.safeServers())
                ConnectionStore.transition(ConnectionState.RESTARTING, selectedTarget.id, selectedTarget.name)
                NirangVpnService.start(context, selectedTarget.id, allowFallback = false)

                when (waitForStart(selectedTarget.id)) {
                    StartResult.CONNECTED -> SafeLog.info(context, "VPN service restarted")
                    StartResult.FAILED -> rollbackSelection(repository, request.previousServerId)
                    StartResult.TIMED_OUT -> {
                        rollbackSelection(repository, request.previousServerId)
                        fail(context, "VPN service did not reconnect in time")
                        NirangVpnService.stopPreservingError(context)
                    }
                }
            }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            fail(context, "VPN restart was interrupted")
        } catch (error: Throwable) {
            SafeLog.error(context, "VPN restart failed: ${error.javaClass.simpleName}")
            fail(context, error.message ?: "VPN restart failed")
            NirangVpnService.stopPreservingError(context)
        } finally {
            draining.set(false)
            if (latest.get() != null && draining.compareAndSet(false, true)) {
                executor.execute { drain(context) }
            }
        }
    }

    private fun waitForStop(expectedGeneration: Long): Boolean {
        val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (stoppedGeneration.get() >= expectedGeneration) return true
            Thread.sleep(POLL_INTERVAL_MS)
        }
        return false
    }

    private fun waitForStart(expectedServerId: String): StartResult {
        val deadline = System.currentTimeMillis() + START_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            val snapshot = ConnectionStore.snapshot()
            val state = ConnectionStore.state()
            if (state == ConnectionState.CONNECTED && snapshot["serverId"] == expectedServerId) {
                return StartResult.CONNECTED
            }
            if (state == ConnectionState.ERROR || state == ConnectionState.DISCONNECTED) {
                return StartResult.FAILED
            }
            Thread.sleep(POLL_INTERVAL_MS)
        }
        return StartResult.TIMED_OUT
    }

    private fun rollbackSelection(repository: SubscriptionRepository, previousServerId: String?) {
        if (previousServerId != null && repository.server(previousServerId) != null) {
            repository.select(previousServerId)
            NativeEvents.emit("servers", repository.safeServers())
        }
    }

    private fun fail(context: Context, message: String) {
        val safeMessage = message
            .replace(Regex("https?://\\S+", RegexOption.IGNORE_CASE), "endpoint")
            .replace(Regex("(?i)(vless|vmess|trojan)://\\S+"), "configuration")
            .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "identifier")
            .take(160)
        SafeLog.warning(context, "VPN restart failed: $safeMessage")
        ConnectionStore.transition(ConnectionState.ERROR, message = safeMessage)
    }

    private enum class StartResult { CONNECTED, FAILED, TIMED_OUT }

    private const val COALESCE_DELAY_MS = 100L
    private const val RESTART_DELAY_MS = 500L
    private const val POLL_INTERVAL_MS = 25L
    private const val STOP_TIMEOUT_MS = 3_000L
    private const val START_TIMEOUT_MS = 15_000L
}
