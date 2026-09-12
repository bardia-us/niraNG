package dev.nirang.client.ping

import java.net.ServerSocket
import org.junit.Assert.assertTrue
import org.junit.Test

class TcpLatencyProbeTest {
    @Test
    fun `TCPing measures a real socket connection independently`() {
        ServerSocket(0).use { server ->
            val delay = TcpLatencyProbe.measure("127.0.0.1", server.localPort, 1_000)
            assertTrue(delay >= 1L)
        }
    }
}
