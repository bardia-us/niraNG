package dev.nirang.client.xray

import android.content.Context
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray

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
    }

    fun stop() = synchronized(lock) {
        if (controller?.isRunning == true) controller?.stopLoop()
    }

    fun isRunning(): Boolean = synchronized(lock) { controller?.isRunning == true }

    fun measureOutboundDelay(config: String, url: String): Long = Libv2ray.measureOutboundDelay(config, url)

    fun version(context: Context): String {
        initialize(context)
        return Libv2ray.checkVersionX()
    }
}
