package dev.nirang.client.cores.singbox

import android.net.VpnService
import android.content.Context
import io.nekohasekai.libbox.*
import java.io.File
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.atomic.AtomicReference

/** Original JSON goes directly to the pinned core after Android capability checks. */
object NativeSingBox {
    const val VERSION = "1.14.4"
    const val SOURCE_COMMIT = "c005f35300ce76427dc285481ec5695f5b179cd2"
    data class Counters(val uplinkTotal: Long, val downlinkTotal: Long, val available: Boolean)
    private val lifecycle = SingBoxLifecycle<Session>()
    private val ownership = dev.nirang.client.vpn.OwnedCoreLifecycle()
    private val traffic = AtomicReference(Counters(0, 0, false))
    @Volatile private var initialized = false

    /** libbox setup paths are process-global; a probe must never repoint a running service. */
    @Synchronized internal fun initialize(context: Context) {
        if (initialized) return
        nirasbgo.Seq.setContext(context.applicationContext)
        val base = File(context.noBackupFilesDir, "sing-box").apply { check(mkdirs() || isDirectory) }
        val working = File(base, "work").apply { check(mkdirs() || isDirectory) }
        val temporary = File(context.cacheDir, "sing-box").apply { check(mkdirs() || isDirectory) }
        Libbox.setup(SetupOptions().apply {
            basePath = base.path; workingPath = working.path; tempPath = temporary.path
            commandServerListenPort = 0
            commandServerSecret = UUID.randomUUID().toString()
            logMaxLines = 0; debug = false; crashReportSource = "native"; oomKillerDisabled = true
        })
        initialized = true
    }

    fun validate(config: String) {
        SingBoxConfigPolicy.validate(config)
        try {
            check(Libbox.version() == VERSION) { "Bundled sing-box version mismatch" }
            Libbox.checkConfig(config)
        } catch (_: LinkageError) {
            throw IllegalStateException("sing-box $VERSION native runtime is unavailable for this Android ABI")
        } catch (_: Exception) {
            // Native errors may contain credential-bearing JSON values. Never forward them to UI/logs.
            throw IllegalArgumentException("sing-box $VERSION rejected this configuration; check its pinned schema")
        }
    }

    fun start(context: VpnService, config: String, tunFd: Int, owner: Any = this, current: () -> Boolean = { true }) = ownership.start(owner,current) {
        require(tunFd == -1) { "sing-box must create its TUN from the original JSON" }
        validate(config)
        traffic.set(Counters(0, 0, false))
        try {
            lifecycle.start({ checkCurrent -> Session(context, {
                if(!current()) throw CancellationException("sing-box start cancelled")
                checkCurrent()
            }, owner) }, { it.start(config) })
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: LinkageError) {
            throw IllegalStateException("sing-box $VERSION native runtime is unavailable for this Android ABI")
        } catch (_: Exception) {
            throw IllegalStateException("sing-box $VERSION could not start the Android VPN session")
        }
    }

    fun stop(owner: Any = this) { ownership.stop(owner) { lifecycle.stop() } }
    fun isRunning() = ownership.isRunning
    fun counters(): Counters = traffic.get()
    fun schema(): String = Libbox.generateConfigSchema().value

    private class Session(private val vpn: VpnService, private val checkCurrent: () -> Unit, private val owner: Any) : AutoCloseable {
        private val platform = SingBoxPlatform(vpn, checkCurrent)
        private var server: CommandServer? = null
        private var client: CommandClient? = null

        fun start(config: String) {
            initialize(vpn)
            platform.prepareNetwork()
            checkCurrent()
            val command = Libbox.newCommandServer(object : CommandServerHandler {
                override fun serviceStop() { Thread { NativeSingBox.stop(owner) }.start() }
                override fun serviceReload() { error("Native reload is disabled") }
                override fun getSystemProxyStatus() = SystemProxyStatus()
                override fun setSystemProxyEnabled(enabled: Boolean) { error("Native system proxy is disabled") }
                override fun triggerNativeCrash() { error("Native debug is disabled") }
                override fun writeDebugMessage(message: String) = Unit
                override fun connectSSHAgent(): Int = error("Native SSH agent is disabled")
            }, platform)
            server = command
            command.start()
            command.startOrReloadService(config, OverrideOptions())
            checkCurrent()
            check(platform.hasTunnel()) { "sing-box did not establish the requested Android TUN" }
            val options = CommandClientOptions().apply {
                addCommand(Libbox.CommandStatus)
                statusInterval = 1_000_000_000L // Go duration, one second
            }
            client = Libbox.newCommandClient(object : CommandClientHandler {
                override fun connected() = Unit
                override fun disconnected(message: String) { traffic.set(traffic.get().copy(available = false)) }
                override fun writeStatus(message: StatusMessage) {
                    if (runCatching { checkCurrent() }.isSuccess) {
                        traffic.set(Counters(message.uplinkTotal, message.downlinkTotal, message.trafficAvailable))
                    }
                }
                override fun setDefaultLogLevel(level: Int) = Unit
                override fun clearLogs() = Unit
                override fun writeLogs(messages: LogIterator) = Unit
                override fun writeGroups(groups: OutboundGroupIterator) = Unit
                override fun writeOutbounds(outbounds: OutboundGroupItemIterator) = Unit
                override fun initializeClashMode(modes: StringIterator, current: String) = Unit
                override fun updateClashMode(mode: String) = Unit
                override fun writeConnectionEvents(events: ConnectionEvents) = Unit
            }, options).also { it.connect() }
        }

        override fun close() {
            runCatching { client?.disconnect() }
            client = null
            try {
                // CommandServer.close only closes observers/transport in pinned 1.14.4.
                // The Box instance and its duplicated TUN FD belong to closeService.
                runCatching { server?.closeService() }
                server?.close()
            } finally {
                server = null
                platform.close()
                traffic.set(traffic.get().copy(available = false))
            }
        }
    }
}
