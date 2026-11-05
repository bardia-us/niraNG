package dev.nirang.client.vpn

import android.net.VpnService
import dev.nirang.client.cores.aether.AetherOptions
import dev.nirang.client.cores.aether.AetherSession
import dev.nirang.client.cores.singbox.NativeSingBox
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.CustomXrayConfig
import dev.nirang.client.xray.XrayConfigBuilder
import dev.nirang.client.xray.XrayCore
import dev.nirang.client.traffic.MeasuredTrafficRepository
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import org.json.JSONObject

/** A service-owned session; ordinary URI connections retain the old Xray builder. */
internal class ConnectionCore(
    private val service: VpnService,
    val server: ServerRecord,
    private val settings: NativeSettings,
    private val iranCidrs: List<String>,
    private val current: () -> Boolean = { true },
) {
    @Volatile private var cancelled = false
    private val endpointProbe=java.util.concurrent.atomic.AtomicReference<dev.nirang.client.ping.ProbeCancellation?>()
    @Volatile private var rememberedEndpoint: String? = null
    val engine = server.customProfile?.engine ?: "xray"
    val ownsTunnel = engine == "sing-box"
    private val includeTun = settings.connectionMode == "vpn"
    private val aether = if(engine == "aether") AetherSession(service.applicationContext,onProgress={ stage ->
        check(current() && !cancelled) { "Connection cancelled" }
        ConnectionStore.updateAetherStage(server.id,stage)
    }, onEndpoint={ path -> if(current() && !cancelled) ConnectionStore.updateAetherEndpoint(server.id,path) }) else null
    private val trafficLock=Any()
    private var trafficWorker:java.util.concurrent.ScheduledExecutorService?=null
    private var trafficFuture:ScheduledFuture<*>?=null
    private var delta=CoreTrafficDelta()
    private var trafficStartedAt=0L
    val configuration: String = when {
        engine == "sing-box" -> server.customProfile!!.payload
        engine == "aether" -> server.customProfile!!.payload
        server.customProfile != null -> CustomXrayConfig.prepare(server.customProfile.payload,includeTun)
        includeTun -> XrayConfigBuilder.buildVpnConfig(server,settings,iranCidrs)
        else -> XrayConfigBuilder.buildProxyConfig(server,settings,iranCidrs)
    }

    fun validate() {
        when(engine) {
            "sing-box" -> { require(includeTun) { "Full sing-box profiles require VPN mode" };NativeSingBox.validate(configuration) }
            "aether" -> aether!!.validate(configuration)
            "xray" -> if(server.customProfile == null) XrayConfigBuilder.validateGeneratedConfig(configuration)
            else -> error("Unsupported connection engine")
        }
    }

    fun start(fd: Int) {
        validate()
        check(current() && !cancelled) { "Connection cancelled" }
        when(engine) {
            "sing-box" -> {
                NativeSingBox.start(service,configuration,-1,this) { current() && !cancelled }
                synchronized(trafficLock) {
                    check(current() && NativeSingBox.isRunning()) { "Connection cancelled" }
                    delta=CoreTrafficDelta();trafficStartedAt=android.os.SystemClock.elapsedRealtime()
                    MeasuredTrafficRepository.get(service).begin()
                    trafficWorker=Executors.newSingleThreadScheduledExecutor { r->Thread(r,"singbox-traffic").apply { isDaemon=true } }
                    trafficFuture=trafficWorker!!.scheduleWithFixedDelay({sampleTraffic()},5,5,TimeUnit.SECONDS)
                }
            }
            "aether" -> {
                aether!!.start(service,configuration,fd)
                if(current() && !cancelled) aether.selectedPath?.let { ConnectionStore.updateAetherEndpoint(server.id,it) }
                val proxy=ServerRecord("aether-egress",server.name,"","socks","127.0.0.1",aether.outputSocksPort,"","tcp","none",emptyMap())
                val config=if(includeTun) XrayConfigBuilder.buildVpnConfig(proxy,settings,iranCidrs)
                    else XrayConfigBuilder.buildProxyConfig(proxy,settings,iranCidrs)
                try { XrayCore.start(service,config,fd,this) { current() && !cancelled } } catch(error:Throwable) { aether.stop();throw error }
            }
            else -> if(server.customProfile != null) XrayCore.startCustom(service,configuration,fd,this) { current() && !cancelled }
                else XrayCore.start(service,configuration,fd,this) { current() && !cancelled }
        }
        if (!current() || cancelled) { stop(); error("Connection cancelled") }
    }
    fun prepare() { aether?.prepare(configuration,if(XrayCore.isRunning()) 10809 else 0) }

    fun diagnosticCurrent():Boolean = current() && !cancelled
    fun diagnosticRunning():Boolean = diagnosticCurrent() && isRunning()
    fun diagnosticSocksPort():Int? {
        if(engine=="aether") return aether?.outputSocksPort
        if(server.customProfile==null) return settings.localSocksPort
        // Only inspect the actual configured inputs; never invent a probe input
        // or replace the user's full JSON just to make diagnostics available.
        val inputs=runCatching { JSONObject(configuration).optJSONArray("inbounds") }.getOrNull() ?: return null
        for(i in 0 until inputs.length()) {
            val node=inputs.optJSONObject(i) ?: continue
            if(node.optString("listen") !in setOf("127.0.0.1","::1","localhost")) continue
            if(node.optString("listen")=="::1") continue // probe helper uses IPv4 loopback
            val type=node.optString(if(engine=="sing-box") "type" else "protocol")
            if(type !in setOf("socks","mixed")) continue
            if(engine=="sing-box" && (node.optJSONArray("users")?.length() ?: 0)>0) continue
            if(engine!="sing-box" && node.optJSONObject("settings")?.optString("auth","noauth") !in setOf(null,"","noauth")) continue
            val port=node.optInt(if(engine=="sing-box") "listen_port" else "port")
            if(port in 1024..65535) return port
        }
        return null
    }

    /** Called on the existing diagnostic worker after a successful IP check.
     * Verify the Aether helper itself: wrapper routing may bypass an IP-check
     * hostname, so a successful wrapper request alone must not teach history. */
    fun rememberAetherEndpoint(network:dev.nirang.client.cores.aether.EndpointNetwork?) {
        val session=aether ?: return
        if(network==null || !diagnosticRunning()) return
        if(dev.nirang.client.cores.aether.AetherEndpointMemory.network(service)?.handle!=network.handle) return
        val path=session.selectedPath ?: return
        val stamp="${network.handle}:$path"
        if(rememberedEndpoint==stamp) return
        val probe=dev.nirang.client.ping.ProbeCancellation(AsyncNativeStop::execute)
        if(!endpointProbe.compareAndSet(null,probe)) return
        try {
            if(!diagnosticCurrent()) return
            dev.nirang.client.ping.SocksHttpLatencyProbe.measure(session.outputSocksPort,"https://www.gstatic.com/generate_204",probe,3000)
            if(diagnosticCurrent() && session.selectedPath==path) {
                dev.nirang.client.cores.aether.AetherEndpointMemory.record(service,configuration,path,network)
                rememberedEndpoint=stamp
            }
        } finally { endpointProbe.compareAndSet(probe,null);probe.cancel() }
    }

    fun stop() {
        endpointProbe.getAndSet(null)?.cancel()
        if(ownsTunnel) {
            synchronized(trafficLock) {
                trafficFuture?.cancel(false);trafficFuture=null
                if(trafficWorker != null) { sampleTraffic();MeasuredTrafficRepository.get(service).end() }
                trafficWorker?.shutdown();trafficWorker=null
            }
            NativeSingBox.stop(this)
        } else { aether?.stop();XrayCore.stop(this) }
    }
    /** Invalidated synchronously before potentially blocking native teardown is queued. */
    fun cancel() { cancelled = true;endpointProbe.getAndSet(null)?.cancel() }
    private fun sampleTraffic()=synchronized(trafficLock) {
        if(trafficWorker == null) return@synchronized
        val counters=NativeSingBox.counters()
        if(counters.available) MeasuredTrafficRepository.get(service).record(delta.sample(counters.uplinkTotal,counters.downlinkTotal))
        else if(android.os.SystemClock.elapsedRealtime()-trafficStartedAt >= 10000) MeasuredTrafficRepository.get(service).record(null)
    }
    fun isRunning(): Boolean = if(ownsTunnel) NativeSingBox.isRunning() else XrayCore.isRunning() && (aether?.isRunning() ?: true)

    fun canCheckIp(): Boolean {
        if(!ownsTunnel) return true
        val inputs=JSONObject(configuration).optJSONArray("inbounds") ?: return false
        return (0 until inputs.length()).any { index ->
            val input=inputs.optJSONObject(index)
            input != null && input.optString("type") in setOf("http","mixed") &&
                input.optString("listen") == "127.0.0.1" && input.optInt("listen_port") == 10809 &&
                (input.optJSONArray("users")?.length() ?: 0) == 0
        }
    }

    fun tunMtu():Int = if(server.customProfile?.engine == "xray") {
        val inputs=JSONObject(configuration).getJSONArray("inbounds")
        (0 until inputs.length()).map { inputs.getJSONObject(it) }.firstOrNull { it.optString("protocol") == "tun" }
            ?.optJSONObject("settings")?.optInt("mtu",1500) ?: 1500
    } else settings.vpnMtu
}
