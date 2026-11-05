package dev.nirang.client.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.telephony.TelephonyManager
import dev.nirang.client.ping.ProbeCancellation
import java.net.Proxy
import java.net.URL
import java.util.concurrent.SynchronousQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection

/** Explicit diagnostic only: never changes process/VPN binding or connection settings. */
internal object UnderlyingNetworkProbe {
    data class Result(val kind:String,val carrier:String,val status:String,val detail:String,val ms:Long?)
    private data class Link(val network:Network,val kind:String,val carrier:String)
    // A stalled OS DNS call cannot create an unbounded queue/threads. A second
    // request returns unknown until the one physical-network worker exits.
    private val worker=ThreadPoolExecutor(1,1,0L,TimeUnit.MILLISECONDS,SynchronousQueue<Runnable>(),
        { task -> Thread(task,"nirang-underlying-check").apply { isDaemon=true } },ThreadPoolExecutor.AbortPolicy())

    private fun select(context:Context):Link? {
        val cm=context.getSystemService(ConnectivityManager::class.java) ?: return null
        fun physical(n:Network)=cm.getNetworkCapabilities(n)?.let {
            it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) && !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        }==true
        val n=NirangVpnService.diagnosticUnderlyingNetwork()?.takeIf(::physical)
            ?: cm.activeNetwork?.takeIf(::physical)
            ?: cm.allNetworks.filter(::physical).sortedByDescending {
                cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)==true
            }.firstOrNull() ?: return null
        val caps=cm.getNetworkCapabilities(n) ?: return null
        val kind=when { caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)->"wifi";caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)->"mobile";else->"other" }
        val carrier=if(kind!="mobile") "" else runCatching {
            val base=context.getSystemService(TelephonyManager::class.java)
            val id=android.telephony.SubscriptionManager.getDefaultDataSubscriptionId()
            val tm=if(id>=0) base.createForSubscriptionId(id) else base
            val text=tm.networkOperatorName.orEmpty().replace(Regex("[\\u0000-\\u001f\\u007f]")," ").trim()
            val points=text.codePoints().limit(20).toArray();String(points,0,points.size)
        }.getOrDefault("")
        return Link(n,kind,carrier)
    }

    fun run(context:Context,cancel:ProbeCancellation):Result {
        cancel.check()
        val link=try { select(context) } catch(_:SecurityException) { return Result("none","","unknown","direct_unknown",null) }
            ?: return Result("none","","warning","no_network",null)
        if(NirangVpnService.diagnosticLockdown()) return Result(link.kind,link.carrier,"unknown","direct_unknown",null)
        val active=AtomicReference<HttpsURLConnection?>()
        val start=System.nanoTime()
        val end=start+TimeUnit.SECONDS.toNanos(3)
        fun remaining():Int {
            val millis=(end-System.nanoTime()+999999)/1000000
            if(millis<=0) throw java.net.SocketTimeoutException("Physical-network check timed out")
            return millis.coerceAtMost(3000).toInt()
        }
        val future=try { worker.submit<Result> {
            try {
                cancel.check();remaining()
                // Network owns DNS and sockets. NO_PROXY prevents reuse of a
                // system/HTTP proxy; default TLS hostname/CA checks remain on.
                val connection=link.network.openConnection(URL("https://www.gstatic.com/generate_204"),Proxy.NO_PROXY) as HttpsURLConnection
                active.set(connection)
                cancel.check();remaining()
                connection.apply {
                    connectTimeout=remaining();readTimeout=remaining()
                    instanceFollowRedirects=false;useCaches=false
                    setRequestProperty("Connection","close")
                    setRequestProperty("Cache-Control","no-cache")
                }
                val code=connection.responseCode
                cancel.check();remaining()
                if(select(context)?.network!=link.network) Result(link.kind,link.carrier,"unknown","network_changed",null)
                else if(code==204) Result(link.kind,link.carrier,"pass","direct_https_ok",TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start).coerceAtLeast(1))
                else Result(link.kind,link.carrier,"fail","direct_https_failed",null)
            } catch(_:SecurityException) { Result(link.kind,link.carrier,"unknown","direct_unknown",null) }
            catch(_:Exception) {
                cancel.check()
                if(select(context)?.network!=link.network) Result(link.kind,link.carrier,"unknown","network_changed",null)
                else Result(link.kind,link.carrier,"fail","direct_https_failed",null)
            } finally { active.getAndSet(null)?.disconnect() }
        } } catch(_:java.util.concurrent.RejectedExecutionException) { return Result(link.kind,link.carrier,"unknown","direct_unknown",null) }
        cancel.own { future.cancel(true);active.getAndSet(null)?.disconnect() }
        return try { future.get(3,TimeUnit.SECONDS).also { cancel.check() } }
        catch(_:Exception) {
            cancel.check()
            val changed=runCatching { select(context)?.network!=link.network }.getOrDefault(false)
            Result(link.kind,link.carrier,if(changed) "unknown" else "fail",if(changed) "network_changed" else "direct_https_failed",null)
        } finally { future.cancel(true);active.getAndSet(null)?.disconnect() }
    }
}
