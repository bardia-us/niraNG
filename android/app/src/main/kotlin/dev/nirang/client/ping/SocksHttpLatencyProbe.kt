package dev.nirang.client.ping

import java.io.EOFException
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.net.SocketTimeoutException
import java.net.URI
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/** Same criterion as the native delay helper: best of two complete 200/204 GETs, with reuse. */
internal object SocksHttpLatencyProbe {
    private val deadlines=Executors.newSingleThreadScheduledExecutor { Thread(it,"probe-http-deadline").apply { isDaemon=true } }

    /** TCP destination reached through the same SOCKS tunnel; not a local-listener ping. */
    fun measureTcp(port: Int, cancellation: ProbeCancellation, timeoutMillis: Int = 3000): Long {
        val active=AtomicReference<Socket?>()
        val start=System.nanoTime()
        val deadline=start+TimeUnit.MILLISECONDS.toNanos(timeoutMillis.toLong())
        val expiry=deadlines.schedule({ runCatching { active.get()?.close() } },timeoutMillis.toLong(),TimeUnit.MILLISECONDS)
        try {
            cancellation.check()
            connect(port,URI("http://www.gstatic.com:443"),cancellation,deadline,active).use {
                cancellation.check(); remaining(deadline)
                return TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start).coerceAtLeast(1)
            }
        } finally { expiry.cancel(false);active.getAndSet(null)?.let { runCatching { it.close() } } }
    }

    fun measure(port: Int, url: String, cancellation: ProbeCancellation, timeoutMillis: Int = 4000): Long {
        val uri=URI(url)
        require(uri.scheme in setOf("http","https") && uri.host != null && uri.rawUserInfo == null)
        require(timeoutMillis>0)
        val deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(timeoutMillis.toLong())
        val active=AtomicReference<Socket?>()
        // A read timeout alone is insufficient for slow streaming bodies or blocked TLS/write calls.
        val expiry=deadlines.schedule({ runCatching { active.get()?.close() } },timeoutMillis.toLong(),TimeUnit.MILLISECONDS)
        var transport: Socket?=null
        var best: Long?=null
        var failure: IOException=SocketTimeoutException("Latency probe budget exhausted")
        try {
            repeat(2) {
                cancellation.check()
                if(System.nanoTime()>=deadline) return@repeat
                val started=System.nanoTime()
                try {
                    val connection=transport ?: connect(port,uri,cancellation,deadline,active).also { transport=it }
                    val reusable=request(connection,uri,cancellation,deadline)
                    val elapsed=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started)
                    best=best?.let { minOf(it,elapsed) } ?: elapsed
                    if(!reusable) { connection.close(); transport=null; active.set(null) }
                } catch(error: IOException) {
                    cancellation.check()
                    failure=error
                    runCatching { transport?.close() }
                    transport=null
                    active.getAndSet(null)?.let { runCatching { it.close() } }
                }
            }
            cancellation.check()
            return best ?: throw failure
        } finally {
            expiry.cancel(false)
            active.getAndSet(null)?.let { runCatching { it.close() } }
        }
    }

    private fun remaining(deadline: Long): Int {
        val nanos=deadline-System.nanoTime()
        if(nanos<=0) throw SocketTimeoutException("Latency probe budget exhausted")
        return TimeUnit.NANOSECONDS.toMillis(nanos).coerceAtLeast(1).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    private fun connect(port: Int, uri: URI, cancellation: ProbeCancellation, deadline: Long, active: AtomicReference<Socket?>): Socket {
        val secure=uri.scheme=="https"
        val targetPort=uri.port.takeIf { it>0 } ?: if(secure) 443 else 80
        val socket=Socket(Proxy(Proxy.Type.SOCKS,InetSocketAddress("127.0.0.1",port)))
        active.set(socket); cancellation.own { socket.close() }
        socket.tcpNoDelay=true
        socket.soTimeout=remaining(deadline)
        // DNS remains inside the selected core, including full JSON routing and DNS policies.
        socket.connect(InetSocketAddress.createUnresolved(uri.host,targetPort),remaining(deadline))
        if(!secure) return socket
        val tls=(SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(socket,uri.host,targetPort,true) as SSLSocket
        active.set(tls); cancellation.own { tls.close() }
        tls.soTimeout=remaining(deadline)
        tls.sslParameters=tls.sslParameters.apply { endpointIdentificationAlgorithm="HTTPS" }
        tls.startHandshake()
        cancellation.check()
        return tls
    }

    private fun request(socket: Socket, uri: URI, cancellation: ProbeCancellation, deadline: Long): Boolean {
        cancellation.check(); socket.soTimeout=remaining(deadline)
        val path=(uri.rawPath?.takeIf { it.isNotEmpty() } ?: "/")+(uri.rawQuery?.let { "?$it" } ?: "")
        val host=uri.rawAuthority
        socket.outputStream.write("GET $path HTTP/1.1\r\nHost: $host\r\nAccept-Encoding: identity\r\nConnection: keep-alive\r\n\r\n".toByteArray(Charsets.US_ASCII))
        socket.outputStream.flush()
        val response=Response(socket,cancellation,deadline)
        val status=Regex("HTTP/1\\.([01]) ([0-9]{3})(?: .*)?").matchEntire(response.line())
            ?: throw IOException("Proxy returned an invalid HTTP status")
        val code=status.groupValues[2].toInt()
        val headers=mutableMapOf<String,String>()
        response.headers(headers)
        if(code!=200 && code!=204) throw IOException("Latency endpoint did not return 200 or 204")
        var reusable=status.groupValues[1]=="1" || headers["connection"].equals("keep-alive",true)
        if(headers["connection"]?.split(',')?.any { it.trim().equals("close",true) }==true) reusable=false
        if(code==204) {
            if(headers.containsKey("transfer-encoding") || headers["content-length"]?.let { it!="0" }==true) reusable=false
        } else {
            val transfer=headers["transfer-encoding"]
            val length=headers["content-length"]
            when {
                transfer!=null -> {
                    if(!transfer.equals("chunked",true) || length!=null) throw IOException("Unsupported HTTP body framing")
                    response.chunks()
                }
                length!=null -> response.drain(length.toLongOrNull()?.takeIf { it>=0 } ?: throw IOException("Invalid HTTP body length"))
                else -> { response.untilEnd(); reusable=false }
            }
        }
        cancellation.check(); remaining(deadline)
        return reusable
    }

    /** Bounded HTTP/1 framing prevents status-only or truncated responses from becoming successful pings. */
    private class Response(val socket: Socket, val cancellation: ProbeCancellation, val deadline: Long) {
        private val input=socket.inputStream
        private val buffer=ByteArray(8192)
        private var headerBytes=0
        private fun beforeRead() { cancellation.check(); socket.soTimeout=remaining(deadline) }
        fun line(): String {
            val result=StringBuilder()
            while(result.length<8192) {
                beforeRead(); val next=input.read()
                if(next<0) throw EOFException("Truncated HTTP response")
                if(++headerBytes>65536) throw IOException("HTTP headers too large")
                if(next==10) {
                    if(result.isEmpty() || result.last()!='\r') throw IOException("Invalid HTTP line ending")
                    return result.dropLast(1).toString()
                }
                result.append(next.toChar())
            }
            throw IOException("HTTP line too large")
        }
        fun headers(target: MutableMap<String,String>) {
            while(true) {
                val line=line(); if(line.isEmpty()) return
                val colon=line.indexOf(':'); if(colon<=0) throw IOException("Invalid HTTP header")
                val name=line.substring(0,colon).lowercase(java.util.Locale.ROOT)
                val value=line.substring(colon+1).trim()
                val previous=target[name]
                if(previous==null) target[name]=value
                else when(name) {
                    "content-length" -> if(previous!=value) throw IOException("Conflicting HTTP body lengths")
                    "transfer-encoding" -> throw IOException("Duplicate HTTP body framing")
                    else -> target[name]="$previous,$value"
                }
            }
        }
        fun drain(length: Long) {
            var left=length
            while(left>0) {
                beforeRead(); val count=input.read(buffer,0,minOf(buffer.size.toLong(),left).toInt())
                if(count<0) throw EOFException("Truncated HTTP body")
                left-=count
            }
        }
        fun untilEnd() { while(true) { beforeRead(); if(input.read(buffer)<0) return } }
        fun chunks() {
            while(true) {
                val length=line().substringBefore(';').trim().toLongOrNull(16)?.takeIf { it>=0 }
                    ?: throw IOException("Invalid HTTP chunk length")
                if(length==0L) { headers(mutableMapOf()); return }
                drain(length)
                if(line().isNotEmpty()) throw IOException("Invalid HTTP chunk ending")
            }
        }
    }
}
