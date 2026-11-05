package dev.nirang.client.cores.aether

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.telephony.TelephonyManager
import dev.nirang.client.subscription.SecureSubscriptionCache
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/** Permission-free network categories, not a claim to identify individual Wi-Fi SSIDs. */
internal data class EndpointNetwork(val bucket: String, val kind: String, val carrier: String, val handle: Long)

internal object AetherEndpointMemory {
    private val lock=Any()
    private const val MAX_AGE=14L*24*60*60*1000
    fun network(context: Context): EndpointNetwork? { return runCatching {
        val cm=context.getSystemService(ConnectivityManager::class.java)
        fun suitable(n: android.net.Network): Boolean = cm.getNetworkCapabilities(n)?.let {
            it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) && !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        } == true
        val n=cm.activeNetwork?.takeIf(::suitable) ?: cm.allNetworks.filter(::suitable)
            .sortedByDescending { cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)==true }.firstOrNull() ?: return null
        val caps=cm.getNetworkCapabilities(n) ?: return null
        val kind=when { caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)->"wifi";caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)->"mobile";else->"other" }
        val baseTm=context.getSystemService(TelephonyManager::class.java)
        val tm=runCatching {
            val id=android.telephony.SubscriptionManager.getDefaultDataSubscriptionId()
            if(id>=0) baseTm.createForSubscriptionId(id) else baseTm
        }.getOrDefault(baseTm)
        val code=if(kind=="mobile") runCatching { tm.networkOperator }.getOrDefault("") else ""
        val carrier=if(kind=="mobile") runCatching { tm.networkOperatorName.take(40) }.getOrDefault("") else ""
        EndpointNetwork("$kind:$code",kind,carrier,n.networkHandle)
    }.getOrNull() }

    private fun key(o:AetherOptions,n:EndpointNetwork):String = MessageDigest.getInstance("SHA-256")
        .digest(listOf(n.bucket,o.mode,o.carrier,o.ipFamily,o.fingerprint,o.psiphon,o.psiphonMode,o.psiphonRegion).joinToString("|").toByteArray())
        .joinToString("") { "%02x".format(it.toInt() and 255) }
    private fun file(context:Context)=File(context.noBackupFilesDir,"aether-endpoint-history.enc")
    private fun read(context:Context):JSONObject {
        val f=file(context)
        if(!f.exists()) return JSONObject()
        require(f.length() in 1..65536)
        return JSONObject(SecureSubscriptionCache.read(f).text)
    }

    fun record(context:Context,payload:String,path:Map<String,String>,expected:EndpointNetwork?) {
        val nowNetwork=network(context) ?: return
        if(expected==null || nowNetwork.handle!=expected.handle || nowNetwork.bucket!=expected.bucket) return
        val o=AetherOptions.parse(payload)
        if(o.psiphon=="only") return
        val endpoints=JSONObject()
        val outer=path["endpoint"] ?: return
        val nested=o.mode in setOf("wireguard-over-masque","warp-in-warp","masque-in-masque")
        endpoints.put(if(nested) "outerEndpoint" else "endpoint",outer)
        if(nested) path["innerEndpoint"]?.let { endpoints.put("innerEndpoint",it) }
        val validation=JSONObject(payload).apply {
            remove("endpoint");remove("outerEndpoint");remove("innerEndpoint");remove("endpointHistory")
            endpoints.keys().forEach { put(it,endpoints.get(it)) }
        }
        AetherOptions.parse(validation.toString())
        synchronized(lock) {
            val root=read(context);val now=System.currentTimeMillis()
            root.keys().asSequence().toList().forEach { k ->
                val time=root.optJSONObject(k)?.optLong("at") ?: 0L
                if(now-time !in 0..MAX_AGE) root.remove(k)
            }
            root.put(key(o,nowNetwork),JSONObject().put("at",now).put("endpoints",endpoints))
            while(root.length()>64) root.remove(root.keys().asSequence().minBy { root.optJSONObject(it)?.optLong("at") ?: 0L })
            SecureSubscriptionCache.writeAtomic(file(context),root.toString())
        }
    }

    fun suggestion(context:Context,payload:String):Map<String,Any?> {
        val o=AetherOptions.parse(payload)
        val n=network(context) ?: return mapOf("available" to false)
        if(o.psiphon=="only") return mapOf("available" to false,"kind" to n.kind,"carrier" to n.carrier)
        val entry=synchronized(lock) { read(context).optJSONObject(key(o,n)) }
        val at=entry?.optLong("at") ?: 0L
        if(entry==null || System.currentTimeMillis()-at !in 0..MAX_AGE) return mapOf("available" to false,"kind" to n.kind,"carrier" to n.carrier)
        val e=entry.getJSONObject("endpoints")
        // Revalidate retained numeric values before returning them to the editor.
        val candidate=JSONObject(payload).apply {
            remove("endpoint");remove("outerEndpoint");remove("innerEndpoint");remove("endpointHistory")
            e.keys().forEach { k -> require(k in setOf("endpoint","outerEndpoint","innerEndpoint"));put(k,e.getString(k)) }
        }
        AetherOptions.parse(candidate.toString())
        return mapOf("available" to true,"kind" to n.kind,"carrier" to n.carrier,"at" to at,
            "endpoints" to e.keys().asSequence().associateWith { e.getString(it) })
    }
}
