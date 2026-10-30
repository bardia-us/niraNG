package dev.nirang.client.ping

import java.net.InetAddress
import java.net.ServerSocket

/** OS-selected loopback ports stay reserved until immediately before native listener startup. */
internal class PrivateProbePorts private constructor(private val sockets: List<ServerSocket>) : AutoCloseable {
    val ports: List<Int> = sockets.map { it.localPort }
    fun releaseForStart() = close()
    override fun close() { sockets.forEach { runCatching { it.close() } } }
    companion object {
        fun reserve(count: Int): PrivateProbePorts {
            require(count in 1..3)
            val sockets = mutableListOf<ServerSocket>()
            try {
                repeat(count) { sockets += ServerSocket(0,1,InetAddress.getByName("127.0.0.1")) }
                return PrivateProbePorts(sockets)
            } catch (failure: Throwable) { sockets.forEach { it.close() }; throw failure }
        }
    }
}
