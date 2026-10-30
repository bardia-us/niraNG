package dev.nirang.client.xray

import android.content.Context
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import dev.nirang.client.traffic.MeasuredTrafficRepository
import dev.nirang.client.traffic.XrayInboundTraffic
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

internal fun initializeCoreEnvironment(
    filesPath: String,
    initialize: (String, String) -> Unit,
) {
    // The second AndroidLibXrayLite argument is a base64url-encoded XUDP
    // BaseKey, not an installation identifier. Leaving it empty deliberately
    // lets Xray generate and retain a cryptographically random 32-byte key.
    initialize(filesPath, "")
}

object XrayCore {
    private val lock = Any()
    private val lifecycle = dev.nirang.client.vpn.OwnedCoreLifecycle()
    private var activeTunFd = 0
    private var controller: CoreController? = null
    private var traffic: MeasuredTrafficRepository? = null
    private var trafficTask: ScheduledFuture<*>? = null
    private val trafficWorker by lazy {
        Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "nirang-traffic").apply { isDaemon = true }
        }
    }

    fun initialize(context: Context) = synchronized(lock) {
        if (controller != null) return
        Seq.setContext(context.applicationContext)
        initializeCoreEnvironment(context.filesDir.absolutePath, Libv2ray::initCoreEnv)
        controller = Libv2ray.newCoreController(object : CoreCallbackHandler {
            override fun startup(): Long = 0
            override fun shutdown(): Long = 0
            override fun onEmitStatus(code: Long, message: String?): Long = 0
        })
    }

    fun start(context: Context, config: String, tunFd: Int, owner: Any = this, current: () -> Boolean = { true }) = startValidated(context,config,tunFd,false,owner,current)

    fun startCustom(context: Context, config: String, tunFd: Int, owner: Any = this, current: () -> Boolean = { true }) = startValidated(context,config,tunFd,true,owner,current)

    private var customSession = false
    private var inboundTraffic: XrayInboundTraffic? = null
    private var inboundTrafficTags: String? = null
    private fun startValidated(context: Context, config: String, tunFd: Int, custom: Boolean, owner: Any, current: () -> Boolean) = lifecycle.start(owner,current) { synchronized(lock) {
        val runtimeConfig = if(custom) dev.nirang.client.subscription.CustomXrayConfig.prepareRuntime(config,tunFd != 0)
        else config.also(XrayConfigBuilder::validateGeneratedConfig)
        val selectedTags = if (custom) dev.nirang.client.subscription.CustomXrayConfig.trafficInboundTags(runtimeConfig,tunFd != 0) else null
        initialize(context)
        check(controller?.isRunning != true) { "Xray core is already running" }
        controller!!.startLoop(runtimeConfig, tunFd)
        activeTunFd = tunFd
        check(controller!!.isRunning) { "Xray core did not enter running state" }
        customSession=custom
        inboundTraffic = if (custom) XrayInboundTraffic() else null
        inboundTrafficTags = selectedTags
        // Ordinary profiles retain the outbound accounting contract. Full JSON
        // uses cumulative inlet counters, independent of user outbound chains.
        // Both have one consumer, serialized with core start/stop/reconnect.
        runCatching {
            traffic = MeasuredTrafficRepository.get(context)
            traffic!!.begin()
            trafficTask = trafficWorker.scheduleWithFixedDelay({
                synchronized(lock) { sampleTraffic() }
            }, 0, 5, TimeUnit.SECONDS)
        }
    } }

    fun stop(owner: Any = this) = lifecycle.stop(owner) { synchronized(lock) {
        trafficTask?.cancel(false)
        trafficTask = null
        if (controller?.isRunning == true) {
            try {
                val selectedTags = inboundTrafficTags
                if (customSession && selectedTags != null) {
                    // The native helper retains counters through core.Close,
                    // then reads their final values. A pre-close poll alone
                    // loses bytes arriving during native shutdown.
                    val final = runCatching { controller!!.stopLoopAndQueryInboundTrafficStats(selectedTags) }.getOrNull()
                    runCatching { traffic?.record(inboundTraffic?.sample(final)) }
                } else sampleTraffic()
            } finally {
                try { if (controller?.isRunning == true) controller?.stopLoop() }
                finally { runCatching { traffic?.end() } }
            }
        }
        traffic = null
        inboundTraffic = null
        inboundTrafficTags = null
        activeTunFd = 0
    } }

    private fun sampleTraffic() {
        if (controller?.isRunning != true || traffic == null) return
        val raw = if(customSession) {
            val selectedTags = inboundTrafficTags
            val snapshot = if (selectedTags == null) null else runCatching { controller!!.queryInboundTrafficStats(selectedTags) }.getOrNull()
            inboundTraffic?.sample(snapshot)
        } else runCatching { controller!!.queryAllOutboundTrafficStats() }.getOrNull()
        runCatching { traffic?.record(raw) }
    }

    fun isRunning(): Boolean = lifecycle.isRunning

    /** A separate instance, with no TUN or shared listener, retaining the active TUN environment. */
    internal fun startProbe(context: Context, config: String, assertCurrent: () -> Unit): CoreController = lifecycle.serialized {
        synchronized(lock) {
            assertCurrent()
            initialize(context)
            val probe = Libv2ray.newCoreController(object : CoreCallbackHandler {
                override fun startup(): Long = 0
                override fun shutdown(): Long = 0
                override fun onEmitStatus(code: Long, message: String?): Long = 0
            })
            try { probe.startLoop(config, activeTunFd); probe }
            catch (failure: Throwable) { runCatching { probe.stopLoop() }; throw failure }
        }
    }

    fun measureOutboundDelay(config: String, url: String): Long = Libv2ray.measureOutboundDelay(config, url)

    fun version(context: Context): String {
        initialize(context)
        return Libv2ray.checkVersionX()
    }
}
