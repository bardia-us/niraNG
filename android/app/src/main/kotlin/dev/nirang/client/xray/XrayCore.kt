package dev.nirang.client.xray

import android.content.Context
import go.Seq
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.util.UUID

object XrayCore {
    private val lock = Any()
    private var controller: CoreController? = null

    fun initialize(context: Context) = synchronized(lock) {
        if (controller != null) return
        Seq.setContext(context.applicationContext)
        val prefs = context.getSharedPreferences("nirang_installation", Context.MODE_PRIVATE)
        val installationId = prefs.getString("id", null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString("id", it).apply()
        }
        Libv2ray.initCoreEnv(context.filesDir.absolutePath, installationId)
        controller = Libv2ray.newCoreController(object : CoreCallbackHandler {
            override fun startup(): Long = 0
            override fun shutdown(): Long = 0
            override fun onEmitStatus(code: Long, message: String?): Long = 0
        })
    }

    fun start(context: Context, config: String, tunFd: Int) = synchronized(lock) {
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
