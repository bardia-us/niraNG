package dev.nirang.client.ping

import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.TimeUnit

internal object TcpLatencyProbe {
    fun measure(address: String, port: Int, timeoutMillis: Int = 4_000): Long {
        require(address.isNotBlank()) { "TCP target is empty" }
        require(port in 1..65_535) { "TCP target port is invalid" }
        val startedAt = System.nanoTime()
        Socket().use { socket ->
            socket.tcpNoDelay = true
            socket.connect(InetSocketAddress(address, port), timeoutMillis)
        }
        return TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - startedAt).coerceAtLeast(1L)
    }
}
