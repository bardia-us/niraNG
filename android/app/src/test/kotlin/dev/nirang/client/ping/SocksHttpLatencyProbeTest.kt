package dev.nirang.client.ping

import java.io.DataInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.file.Files
import java.security.KeyStore
import java.util.concurrent.CancellationException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLHandshakeException
import javax.net.ssl.SSLSocket
import javax.net.ssl.TrustManagerFactory
import org.junit.Assert.*
import org.junit.Test

class SocksHttpLatencyProbeTest {
    /** A real SOCKS5 peer; the target remains unresolved on the client. */
    private class SocksFixture(private val tls: SSLContext?=null, private val reply: (Socket, Int) -> Unit) : AutoCloseable {
        private val server=ServerSocket(0,10,InetAddress.getByName("127.0.0.1"))
        private val workers=Executors.newCachedThreadPool { Thread(it).apply { isDaemon=true } }
        val connections=AtomicInteger()
        val requests=AtomicInteger()
        val target=java.util.concurrent.atomic.AtomicReference<String>()
        val port: Int get()=server.localPort
        init { workers.submit {
            while(!server.isClosed) {
                val socket=runCatching { server.accept() }.getOrNull() ?: break
                connections.incrementAndGet()
                workers.submit { socket.use { runCatching {
                    socket.soTimeout=1500
                    val input=DataInputStream(socket.inputStream); val output=socket.outputStream
                    check(input.readUnsignedByte()==5)
                    repeat(input.readUnsignedByte()) { input.readUnsignedByte() }
                    output.write(byteArrayOf(5,0)); output.flush()
                    check(input.readUnsignedByte()==5); check(input.readUnsignedByte()==1); input.readUnsignedByte()
                    check(input.readUnsignedByte()==3) { "Client resolved the target outside the core" }
                    val host=ByteArray(input.readUnsignedByte()); input.readFully(host); target.set(String(host))
                    input.readUnsignedShort()
                    output.write(byteArrayOf(5,0,0,1,127,0,0,1,0,80)); output.flush()
                    val transport=if(tls==null) socket else (tls.socketFactory.createSocket(socket,"probe.invalid",443,true) as SSLSocket).apply {
                        useClientMode=false; soTimeout=1500; startHandshake()
                    }
                    val requestsInput=transport.inputStream
                    while(!socket.isClosed) {
                        var tail=""
                        while(!tail.endsWith("\r\n\r\n")) {
                            val byte=requestsInput.read(); if(byte<0) return@runCatching
                            tail=(tail+byte.toChar()).takeLast(4)
                        }
                        reply(transport,requests.incrementAndGet())
                    }
                } } }
            }
        } }
        override fun close() { server.close(); workers.shutdownNow(); workers.awaitTermination(2,TimeUnit.SECONDS) }
    }

    /** Generated test-only key; production always uses the platform trust store and hostname verification. */
    private fun <T> withTlsContexts(action: (SSLContext,SSLContext) -> T): T {
        val directory=Files.createTempDirectory("nirang-ping-tls-")
        val storeFile=directory.resolve("fixture.p12")
        val password="public-test-fixture".toCharArray()
        try {
            val keytool=java.io.File(System.getProperty("java.home"),"bin/keytool.exe").takeIf { it.exists() }
                ?: java.io.File(System.getProperty("java.home"),"bin/keytool")
            val process=ProcessBuilder(keytool.path,"-genkeypair","-alias","fixture","-keyalg","EC","-groupname","secp256r1",
                "-dname","CN=probe.invalid","-ext","SAN=dns:probe.invalid","-validity","2","-storetype","PKCS12",
                "-keystore",storeFile.toString(),"-storepass",String(password)).redirectErrorStream(true).start()
            val output=process.inputStream.bufferedReader().readText()
            check(process.waitFor(20,TimeUnit.SECONDS) && process.exitValue()==0) { "Test certificate generation failed: $output" }
            val store=KeyStore.getInstance("PKCS12").apply { Files.newInputStream(storeFile).use { load(it,password) } }
            val keys=KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(store,password) }
            val trusts=TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm()).apply { init(store) }
            val server=SSLContext.getInstance("TLS").apply { init(keys.keyManagers,null,null) }
            val client=SSLContext.getInstance("TLS").apply { init(null,trusts.trustManagers,null) }
            return action(server,client)
        } finally { Files.deleteIfExists(storeFile); Files.deleteIfExists(directory) }
    }

    @Test fun `HTTPS warm requests retain TLS certificate and hostname validation`(): Unit = withTlsContexts { server,client ->
        val original=SSLContext.getDefault()
        try {
            SSLContext.setDefault(client)
            SocksFixture(server) { socket,attempt ->
                Thread.sleep(if(attempt==1) 300 else 20)
                socket.outputStream.write("HTTP/1.1 204 No Content\r\n\r\n".toByteArray()); socket.outputStream.flush()
            }.use { fixture ->
                val cancellation=ProbeCancellation { it() }
                try {
                    val delay=SocksHttpLatencyProbe.measure(fixture.port,"https://probe.invalid/generate_204",cancellation,3000)
                    assertEquals(2,fixture.requests.get()); assertEquals(1,fixture.connections.get())
                    assertTrue("Warm TLS request included cold handshake: $delay",delay<150)
                } finally { cancellation.cancel() }
            }
            SocksFixture(server) { _,_ -> fail("Wrong hostname must not reach HTTP") }.use { fixture ->
                val cancellation=ProbeCancellation { it() }
                try { assertThrows(SSLHandshakeException::class.java) { SocksHttpLatencyProbe.measure(fixture.port,"https://wrong.invalid/",cancellation) } }
                finally { cancellation.cancel() }
            }
            SSLContext.setDefault(original)
            SocksFixture(server) { _,_ -> fail("Untrusted certificate must not reach HTTP") }.use { fixture ->
                val cancellation=ProbeCancellation { it() }
                try { assertThrows(SSLHandshakeException::class.java) { SocksHttpLatencyProbe.measure(fixture.port,"https://probe.invalid/",cancellation) } }
                finally { cancellation.cancel() }
            }
        } finally { SSLContext.setDefault(original) }
    }

    private fun measure(fixture: SocksFixture, timeout: Int=2000): Long {
        val cancellation=ProbeCancellation { it() }
        try { return SocksHttpLatencyProbe.measure(fixture.port,"http://probe.invalid/generate_204",cancellation,timeout) }
        finally { cancellation.cancel() }
    }

    @Test fun `best of two requests reuses a warm connection instead of reporting cold setup`() {
        SocksFixture { socket,attempt ->
            Thread.sleep(if(attempt==1) 300 else 20)
            socket.outputStream.write("HTTP/1.1 204 No Content\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture ->
            val delay=measure(fixture)
            assertEquals(2,fixture.requests.get()); assertEquals(1,fixture.connections.get())
            assertEquals("probe.invalid",fixture.target.get())
            assertTrue("Warm request should not include the first 300ms: $delay",delay<150)
        }
    }

    @Test fun `chunked success body is fully consumed before connection reuse`() {
        SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4;test=yes\r\nbody\r\n0\r\nTrailer: done\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture -> assertTrue(measure(fixture)>=0); assertEquals(2,fixture.requests.get()); assertEquals(1,fixture.connections.get()) }
    }

    @Test fun `valid repeated response headers do not invalidate real latency`() {
        SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 204 No Content\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture -> assertTrue(measure(fixture)>=0); assertEquals(2,fixture.requests.get()) }
    }

    @Test fun `a completed first response remains valid if the warm attempt exhausts the shared budget`() {
        SocksFixture { socket,attempt ->
            if(attempt==2) Thread.sleep(1000)
            socket.outputStream.write("HTTP/1.1 204 No Content\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture -> assertTrue(measure(fixture,250)>=0); assertEquals(2,fixture.requests.get()) }
    }

    @Test fun `a failed first connection can recover with the second complete response`() {
        SocksFixture { socket,attempt ->
            val status=if(attempt==1) 503 else 204
            socket.outputStream.write("HTTP/1.1 $status Test\r\nContent-Length: 0\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture -> assertTrue(measure(fixture)>=0); assertEquals(2,fixture.requests.get()); assertEquals(2,fixture.connections.get()) }
    }

    @Test fun `closed responses reconnect for the next attempt`() {
        SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 4\r\n\r\nbody".toByteArray()); socket.close()
        }.use { fixture -> assertTrue(measure(fixture)>=0); assertEquals(2,fixture.requests.get()); assertEquals(2,fixture.connections.get()) }
    }

    @Test fun `a truncated successful response cannot produce a ping`() {
        SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\nshort".toByteArray()); socket.close()
        }.use { fixture -> assertThrows(Exception::class.java) { measure(fixture) } }
    }

    @Test fun `HTTP status must match ordinary native probe success criterion`() {
        for(status in listOf(201,302,503)) SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 $status Test\r\nContent-Length: 0\r\n\r\n".toByteArray()); socket.outputStream.flush()
        }.use { fixture -> assertThrows(Exception::class.java) { measure(fixture) } }
    }

    @Test fun `slow streaming response cannot reset the overall deadline`() {
        SocksFixture { socket,_ ->
            socket.outputStream.write("HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n".toByteArray()); socket.outputStream.flush()
            repeat(1000) { socket.outputStream.write(65); socket.outputStream.flush(); Thread.sleep(40) }
        }.use { fixture ->
            val start=System.nanoTime()
            assertThrows(Exception::class.java) { measure(fixture,250) }
            assertTrue("One budget must bound both attempts",TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start)<900)
        }
    }

    @Test fun `cancellation closes a blocked response and never returns a stale success`() {
        val received=CountDownLatch(1)
        SocksFixture { _,_ -> received.countDown(); Thread.sleep(1500) }.use { fixture ->
            val cancellation=ProbeCancellation { it() }
            val executor=Executors.newSingleThreadExecutor()
            try {
                val future=executor.submit<Long> { SocksHttpLatencyProbe.measure(fixture.port,"http://probe.invalid/",cancellation) }
                assertTrue(received.await(2,TimeUnit.SECONDS)); cancellation.cancel()
                val failure=assertThrows(java.util.concurrent.ExecutionException::class.java) { future.get(500,TimeUnit.MILLISECONDS) }
                assertTrue(failure.cause is CancellationException)
            } finally { cancellation.cancel(); executor.shutdownNow() }
        }
    }

    @Test fun `cancel detaches native closers without blocking caller and runs each once`() {
        val dispatched=mutableListOf<()->Unit>(); var closed=0
        val cancellation=ProbeCancellation { dispatched += it }
        cancellation.own { closed++ }; cancellation.cancel(); cancellation.cancel()
        assertEquals(0,closed); assertEquals(1,dispatched.size)
        dispatched.single()(); assertEquals(1,closed)
        assertThrows(CancellationException::class.java) { cancellation.check() }
        assertThrows(CancellationException::class.java) { cancellation.own { closed++ } }
        assertEquals(2,dispatched.size)
    }
}
