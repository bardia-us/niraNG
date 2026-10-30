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
    // Cancellation and the final service commands share one linearization point.
    private val operationLock = Any()
    @Volatile private var preparingAether:dev.nirang.client.cores.aether.AetherSession?=null

    fun request(context: Context, serverId: String): Boolean {
        val appContext = context.applicationContext
        val repository = SubscriptionRepository(appContext)
        val target = repository.server(serverId) ?: return false
        // ConnectionStore may already name a queued replacement. Rollback must
        // retain the service's real current profile across rapid requests.
        synchronized(operationLock) {
            preparingAether?.let { session -> AsyncNativeStop.execute(session::stop) }
            val activeId = NirangVpnService.activeServerId()
            val request = Request(generation.incrementAndGet(), target.id, activeId)
            latest.set(request)
            ConnectionStore.transition(ConnectionState.RESTARTING, target.id, target.name)
        }
        if (draining.compareAndSet(false, true)) executor.execute { drain(appContext) }
        return true
    }

    /** Cancels queued/in-flight restarts so they cannot revive a manually stopped VPN. */
    fun cancel() {
        synchronized(operationLock) {
            generation.incrementAndGet()
            latest.set(null)
            preparingAether?.let { session -> AsyncNativeStop.execute(session::stop) }
        }
    }

    internal fun onServiceStopped(generation: Long) {
        stoppedGeneration.accumulateAndGet(generation, ::maxOf)
    }

    internal fun isCurrentGeneration(token: Long): Boolean = generation.get() == token

    private fun drain(context: Context) {
        try {
            while (!Thread.currentThread().isInterrupted) {
                Thread.sleep(COALESCE_DELAY_MS)
                val request = latest.getAndSet(null) ?: break
                if (!isCurrent(request)) continue
                val repository = SubscriptionRepository(context)
                val target = repository.server(request.serverId)
                if (target == null) {
                    fail(context, "Selected server is no longer available")
                    NirangVpnService.stopPreservingError(context)
                    continue
                }

                // Reject incompatible native JSON before tearing down a healthy
                // connection. Native errors are not echoed with raw profile data.
                try {
                    ConnectionPreflight.validate(context,target)
                    target.customProfile?.takeIf { it.engine == "aether" }?.let { profile ->
                        val preparing=dev.nirang.client.cores.aether.AetherSession(context,onProgress={
                            check(isCurrent(request)) { "Connection preparation cancelled" }
                        })
                        synchronized(operationLock) {
                            check(isCurrent(request)) { "Connection preparation cancelled" }
                            preparingAether=preparing
                        }
                        try {
                            check(isCurrent(request)) { "Connection preparation cancelled" }
                            preparing.prepare(profile.payload,if(dev.nirang.client.xray.XrayCore.isRunning()) 10809 else 0)
                        } finally {
                            preparing.stop()
                            if(preparingAether === preparing) preparingAether=null
                        }
                    }
                } catch (_:Throwable) {
                    if(!isCurrent(request)) continue
                    rollbackSelection(repository,request.previousServerId)
                    val previous=request.previousServerId?.let(repository::server)
                    if(previous != null && (dev.nirang.client.xray.XrayCore.isRunning() || dev.nirang.client.cores.singbox.NativeSingBox.isRunning())) {
                        ConnectionStore.transition(ConnectionState.CONNECTED,previous.id,previous.name,"Profile rejected; current connection was retained")
                    } else fail(context,"Selected profile is not compatible with its Android core")
                    continue
                }

                val stopping = synchronized(operationLock) {
                    if (!isCurrent(request)) false else {
                        NirangVpnService.stopForRestart(context, request.generation, target.id, target.name)
                        true
                    }
                }
                if (!stopping) continue
                if (!waitForStop(request)) {
                    if (!isCurrent(request)) continue
                    NirangVpnService.stopPreservingError(context)
                    fail(context, "VPN service did not stop in time")
                    continue
                }

                // A newer target goes through the next iteration's own preflight.
                if (!isCurrent(request)) continue
                val selectedTarget = target

                Thread.sleep(RESTART_DELAY_MS)
                if (!isCurrent(request)) continue
                val starting = synchronized(operationLock) {
                    if (!isCurrent(request)) false else {
                        repository.select(selectedTarget.id)
                        NativeEvents.emit("servers", repository.safeServers())
                        // A synchronous observer may itself cancel or replace the request.
                        if (!isCurrent(request)) false else {
                            ConnectionStore.transition(ConnectionState.RESTARTING, selectedTarget.id, selectedTarget.name)
                            if (!isCurrent(request)) false else {
                                NirangVpnService.start(context, selectedTarget.id, allowFallback = false)
                                true
                            }
                        }
                    }
                }
                if (!starting) continue

                // Registration was preflighted above. Scan time follows the user's
                // bounded setting, with the ordinary service-start budget added.
                val timeout=if(selectedTarget.customProfile?.engine == "aether") {
                    dev.nirang.client.cores.aether.AetherOptions.parse(selectedTarget.customProfile.payload)
                        .startupTimeoutSeconds * 1_000L + START_TIMEOUT_MS
                } else START_TIMEOUT_MS
                when (waitForStart(request, selectedTarget.id,timeout)) {
                    StartResult.CONNECTED -> SafeLog.info(context, "VPN service restarted")
                    StartResult.FAILED -> rollbackSelection(repository, request.previousServerId)
                    StartResult.CANCELLED -> Unit
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

    private fun waitForStop(request: Request): Boolean {
        val deadline = System.currentTimeMillis() + STOP_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (!isCurrent(request)) return false
            if (stoppedGeneration.get() >= request.generation) return true
            Thread.sleep(POLL_INTERVAL_MS)
        }
        return false
    }

    private fun waitForStart(request: Request, expectedServerId: String, timeoutMillis:Long): StartResult {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            if (!isCurrent(request)) return StartResult.CANCELLED
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

    private fun isCurrent(request: Request): Boolean = isCurrentGeneration(request.generation)

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

    private enum class StartResult { CONNECTED, FAILED, TIMED_OUT, CANCELLED }

    private const val COALESCE_DELAY_MS = 100L
    private const val RESTART_DELAY_MS = 500L
    private const val POLL_INTERVAL_MS = 25L
    private const val STOP_TIMEOUT_MS = 3_000L
    private const val START_TIMEOUT_MS = 15_000L
}
