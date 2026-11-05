package dev.nirang.client.vpn

import android.content.Context
import dev.nirang.client.cores.aether.AetherEndpointMemory
import dev.nirang.client.ping.ProbeCancellation
import dev.nirang.client.ping.SocksHttpLatencyProbe
import dev.nirang.client.model.ConnectionState
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.net.ConnectException
import javax.net.ssl.SSLException

/** Read-only, explicit diagnostics through the existing core; never starts another VPN. */
internal object ConnectionDiagnostics {
    fun run(context:Context,cancel:ProbeCancellation,onRow:(Map<String,Any?>)->Unit = {}):Map<String,Any?> {
        val metadata=linkedMapOf<String,Any?>(
            "app" to "niraNG ${dev.nirang.client.BuildConfig.VERSION_NAME} (${dev.nirang.client.BuildConfig.VERSION_CODE})",
            "androidSdk" to android.os.Build.VERSION.SDK_INT,
            "state" to ConnectionStore.state().name.lowercase(java.util.Locale.ROOT),
        )
        val rows=mutableListOf<Map<String,Any?>>()
        fun row(name:String,status:String,detail:String,ms:Long?=null) { val value=mapOf("name" to name,"status" to status,"detail" to detail,"ms" to ms);rows+=value;onRow(value) }
        val network=AetherEndpointMemory.network(context)
        val initial=UnderlyingNetworkProbe.run(context,cancel)
        metadata["network"] = initial.kind
        if(initial.carrier.isNotBlank()) metadata["carrier"] = initial.carrier
        row("network",initial.status,initial.detail,initial.ms)
        cancel.check()
        val target=NirangVpnService.diagnosticTarget()
        if(target==null || ConnectionStore.state()!=ConnectionState.CONNECTED) {
            row("core","warning",when(ConnectionStore.state()) { ConnectionState.ERROR->"core_error";ConnectionState.DISCONNECTED->"disconnected";else->"busy" })
            row("tcp","unknown","not_tested")
            row("https","unknown","not_tested")
            return mapOf("rows" to rows,"stale" to false,"metadata" to metadata)
        }
        val (id,core)=target
        metadata["engine"] = core.engine.takeIf { it in setOf("xray","sing-box","aether") } ?: "unknown"
        if(core.engine=="aether") runCatching {
            val options=dev.nirang.client.cores.aether.AetherOptions.parse(core.configuration)
            metadata["mode"]=options.mode
            metadata["psiphon"]=options.psiphon
            metadata["fingerprint"]=options.fingerprint
            metadata["ipFamily"]=options.ipFamily
        }
        fun current()=core.diagnosticCurrent() && NirangVpnService.activeServerId()==id && ConnectionStore.state()==ConnectionState.CONNECTED
        val running=core.diagnosticRunning()
        row("core",if(running) "pass" else "fail",if(running) "core_running" else "core_missing")
        val port=if(running) core.diagnosticSocksPort() else null
        if(port==null) {
            row("tcp","unknown",if(running) "no_probe_input" else "not_tested")
            row("https","unknown",if(running) "no_probe_input" else "not_tested")
        }
        else {
            cancel.check()
            var tcpOk=false
            try {
                val ms=SocksHttpLatencyProbe.measureTcp(port,cancel,3000)
                row("tcp","pass","tcp_ok",ms);tcpOk=true
            } catch(e:Exception) {
                cancel.check()
                row("tcp","fail",if(e is SocketTimeoutException) "timeout" else "tcp_failed")
            }
            if(!tcpOk) {
                row("https","unknown","tcp_unavailable")
                return if(!current()) mapOf("rows" to emptyList<Any>(),"stale" to true,"metadata" to metadata)
                else mapOf("rows" to rows,"stale" to false,"metadata" to metadata)
            }
            try {
                // Domain resolution stays in SOCKS/core; TLS hostname/certificate verification remains enabled.
                val ms=SocksHttpLatencyProbe.measure(port,"https://www.gstatic.com/generate_204",cancel,6000)
                row("https","pass","https_ok",ms)
                if(current() && core.engine=="aether") runCatching {
                    val state=ConnectionStore.snapshot()
                    val outer=state["aetherEndpoint"] as? String
                    if(outer!=null) AetherEndpointMemory.record(context,core.configuration,buildMap {
                        put("endpoint",outer);(state["aetherInnerEndpoint"] as? String)?.let { put("innerEndpoint",it) }
                    },network)
                }
            } catch(e:Exception) {
                cancel.check()
                row("https","fail",when(e) {
                    is SocketTimeoutException -> "timeout"
                    is UnknownHostException -> "dns_failed"
                    is SSLException -> "tls_failed"
                    is ConnectException -> "proxy_unreachable"
                    else -> "probe_failed"
                })
            }
        }
        cancel.check()
        return if(!current()) mapOf("rows" to emptyList<Any>(),"stale" to true,"metadata" to metadata) else mapOf("rows" to rows,"stale" to false,"metadata" to metadata)
    }
}
