package dev.nirang.client.xray

import android.content.Context
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import dev.nirang.client.traffic.MeasuredTrafficRepository
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

    fun start(context: Context, config: String, tunFd: Int) = synchronized(lock) {
        XrayConfigBuilder.validateGeneratedConfig(config)
        initialize(context)
        check(controller?.isRunning != true) { "Xray core is already running" }
        controller!!.startLoop(config, tunFd)
        check(controller!!.isRunning) { "Xray core did not enter running state" }
        // The library exposes reset-on-read outbound counters. This is their
        // sole consumer, serialized with every core start/stop/reconnect.
        runCatching {
            traffic = MeasuredTrafficRepository.get(context)
            traffic!!.begin()
            trafficTask = trafficWorker.scheduleWithFixedDelay({
                synchronized(lock) { sampleTraffic() }
            }, 0, 5, TimeUnit.SECONDS)
        }
    }

    fun stop() = synchronized(lock) {
        trafficTask?.cancel(false)
        trafficTask = null
        if (controller?.isRunning == true) {
            sampleTraffic()
            runCatching { traffic?.end() }
            controller?.stopLoop()
        }
    }

    private fun sampleTraffic() {
        if (controller?.isRunning != true || traffic == null) return
        val raw = runCatching { controller!!.queryAllOutboundTrafficStats() }.getOrNull()
        runCatching { traffic?.record(raw) }
    }

    fun isRunning(): Boolean = synchronized(lock) { controller?.isRunning == true }

    fun measureOutboundDelay(config: String, url: String): Long = Libv2ray.measureOutboundDelay(config, url)

    fun version(context: Context): String {
        initialize(context)
        return Libv2ray.checkVersionX()
    }
}
