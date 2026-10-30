package dev.nirang.client.ping

import android.content.Context
import dev.nirang.client.cores.aether.AetherOptions
import dev.nirang.client.cores.aether.AetherSession
import dev.nirang.client.cores.aether.AetherIdentityStore
import dev.nirang.client.cores.singbox.NativeSingBox
import dev.nirang.client.cores.singbox.SingBoxPlatform
import dev.nirang.client.subscription.CustomProfile
import dev.nirang.client.xray.XrayCore
import io.nekohasekai.libbox.*
import java.io.File
import java.util.UUID
import org.json.JSONObject

/** Every cold probe owns its listeners/processes; it never starts or stops the active VPN. */
internal object CustomProfileLatencyProbe {
    private val slots = java.util.concurrent.Semaphore(2)
    fun measure(context: Context, profile: CustomProfile, url: String, cancellation: ProbeCancellation, onStarted: () -> Unit = {}): Long {
        slots.acquire()
        try { cancellation.check(); onStarted(); return measureNative(context,profile,url,cancellation) }
        finally { slots.release() }
    }
    private fun measureNative(context: Context, profile: CustomProfile, url: String, cancellation: ProbeCancellation): Long = when(profile.engine) {
        "xray" -> PrivateProbePorts.reserve(1).use { ports ->
            val config = CustomProbeConfig.xray(profile.payload,ports.ports[0])
            cancellation.check()
            ports.releaseForStart()
            val core = XrayCore.startProbe(context,config,cancellation::check)
            try {
                cancellation.own { core.stopLoop() }
                cancellation.check()
                SocksHttpLatencyProbe.measure(ports.ports[0],url,cancellation)
            } finally { runCatching { core.stopLoop() } }
        }
        "sing-box" -> PrivateProbePorts.reserve(1).use { ports ->
            withDirectory(context.cacheDir,"sing-box-probe") { directory ->
            val config = CustomProbeConfig.singBox(profile.payload,ports.ports[0],File(directory,"cache.db").absolutePath)
            NativeSingBox.initialize(context)
            Libbox.checkConfig(config)
            val platform = SingBoxPlatform(context,{ cancellation.check() },probeOnly=true)
            var closeCommand: () -> Unit = {}
            try {
                cancellation.own(platform::close)
                platform.prepareNetwork()
                cancellation.check()
                val session = Libbox.newCommandServer(object : CommandServerHandler {
                    override fun serviceStop() = Unit
                    override fun serviceReload() { error("Probe reload is disabled") }
                    override fun getSystemProxyStatus() = SystemProxyStatus()
                    override fun setSystemProxyEnabled(enabled: Boolean) { error("Probe system proxy is disabled") }
                    override fun triggerNativeCrash() { error("Probe debug is disabled") }
                    override fun writeDebugMessage(message: String) = Unit
                    override fun connectSSHAgent(): Int = error("Probe SSH agent is disabled")
                },platform)
                closeCommand = closeOnce {
                    try { session.closeService() } finally { session.close() }
                }
                cancellation.own(closeCommand)
                cancellation.check()
                ports.releaseForStart()
                // This additive pinned binding skips active configuration snapshots and control listeners.
                session.startProbe(config)
                cancellation.check()
                SocksHttpLatencyProbe.measure(ports.ports[0],url,cancellation)
            } finally { runCatching(closeCommand); platform.close() }
            }
        }
        "aether" -> aether(context,profile.payload,url,cancellation)
        else -> error("Unsupported latency engine")
    }

    private fun aether(context: Context, payload: String, url: String, cancellation: ProbeCancellation): Long = PrivateProbePorts.reserve(2).use { ports ->
        withDirectory(context.noBackupFilesDir,"aether-probe") { directory ->
        val config = JSONObject(payload).apply { put("startupTimeoutSeconds",minOf(optInt("startupTimeoutSeconds",180),45)) }.toString()
        val options = AetherOptions.parse(config)
        val session = AetherSession(context,socksPort=ports.ports[0],psiphonPort=ports.ports[1],
            onProgress={ cancellation.check() },storageDirectory=directory)
        val stop = closeOnce(session::stop)
        try {
            cancellation.own(stop)
            AetherIdentityStore(File(context.noBackupFilesDir,"aether")).copyRetained(options,directory)
            cancellation.check()
            ports.releaseForStart()
            session.scan(config)
            cancellation.check()
            SocksHttpLatencyProbe.measure(session.outputSocksPort,url,cancellation)
        } finally {
            stop()
        }
        }
    }

    private fun <T> withDirectory(parent: File, prefix: String, action: (File) -> T): T {
        val directory=File(parent,"$prefix-${UUID.randomUUID()}")
        check(directory.mkdir()) { "Could not create private probe storage" }
        try {
            android.system.Os.chmod(directory.absolutePath,448)
            return action(directory)
        } finally {
            // Only this operation's UUID-named private directory can be removed.
            directory.deleteRecursively()
        }
    }

    /** Both timeout cancellation and worker-finally join the same completed native close. */
    private fun closeOnce(action: () -> Unit): () -> Unit {
        val lock=Any()
        var closed=false
        return { synchronized(lock) { if(!closed) { closed=true; action() } } }
    }
}
