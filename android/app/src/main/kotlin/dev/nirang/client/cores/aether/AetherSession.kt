package dev.nirang.client.cores.aether

import android.content.Context
import android.net.VpnService
import android.os.Build
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.Socket
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory
import org.json.JSONObject

/**
 * Runs the hardened, pinned Aether executable. The service retains ownership of TUN/Xray.
 * The service MUST exclude its own UID using its existing PerAppPolicy. Alternatively supply
 * a UDP-capable, protected direct SOCKS upstream. Blocking calls belong on the VPN worker.
 */
class AetherSession(
    context: Context,
    private val protectedUpstreamPort: Int = 0,
    private val socksPort: Int = 10819,
    private val psiphonPort: Int = 10821,
    private val onProgress: (String) -> Unit = {},
    private val storageDirectory: File? = null,
    private val onEndpoint: (Map<String,String>) -> Unit = {},
) {
    private val app = context.applicationContext
    private val owner = AetherProcessOwner()
    private val directory get() = storageDirectory ?: File(app.noBackupFilesDir, "aether")
    @Volatile private var live: Process? = null
    @Volatile private var ready = false
    @Volatile var selectedPath: Map<String,String>? = null
        private set
    @Volatile var outputSocksPort: Int = socksPort
        private set

    fun validate(config: String) {
        val options = AetherOptions.parse(config)
        require(Build.VERSION.SDK_INT >= 29) { "Aether requires Android 10 or later" }
        require(protectedUpstreamPort == 0 || protectedUpstreamPort in 1024..65535)
        runtimeFiles(options)
        options.arguments(directory, socksPort, psiphonPort, protectedUpstreamPort)
    }

    /** Safe before stopping an existing connection. Explicit HTTP proxy is used only for registration. */
    fun prepare(config: String, upstreamHttpPort: Int = 0, forceRenew: Boolean = false) {
        validate(config)
        require(upstreamHttpPort == 0 || upstreamHttpPort in 1024..65535)
        val token = owner.begin()
        try {
            val options=AetherOptions.parse(config)
            require(!forceRenew || options.identityFiles.isNotEmpty()) { "Psiphon-only does not use a WARP identity" }
            provision(options, token, upstreamHttpPort, forceRenew)
        }
        finally { owner.finish(token) }
    }

    @Suppress("UNUSED_PARAMETER")
    fun start(service: VpnService, config: String, tunFd: Int) = startInternal(config, false)

    /** Explicit rescan ignores the retained endpoint; startup timeout also bounds the scan. */
    fun rescan(service: VpnService, config: String, tunFd: Int) = startInternal(config, true)

    /** Standalone scan keeps a temporary local proxy until its caller stops it in finally. */
    fun scan(config: String) = startInternal(config, true, verifyPath = true)

    private fun startInternal(config: String, rescan: Boolean, verifyPath: Boolean = false) {
        validate(config)
        val token = owner.begin()
        ready = false
        val options = AetherOptions.parse(config)
        // A configured peer is not evidence that the core selected it.
        selectedPath = null
        try {
            provision(options, token, 0)
            checkCurrent(token)
            onProgress("finding_endpoint")
            outputSocksPort = options.outputPort(socksPort, psiphonPort)
            val process = launch(options, options.arguments(directory, socksPort, psiphonPort,
                protectedUpstreamPort, rescan = rescan), token)
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(options.startupTimeoutSeconds.toLong())
            while (System.nanoTime() < deadline) {
                checkCurrent(token)
                check(process.isAlive) { "Aether stopped before establishing a tunnel" }
                if (if (verifyPath) probe(options.psiphon == "off") else localListenerReady()) {
                    checkCurrent(token)
                    ready = true
                    onProgress("ready")
                    return
                }
                Thread.sleep(250)
            }
            throw IllegalStateException("Aether could not find a working path in time; retry or rescan on another network")
        } catch (failure: Throwable) {
            owner.finish(token)
            throw failure
        }
    }

    private fun provision(options: AetherOptions, token: Long, upstreamHttpPort: Int, forceRenew: Boolean = false) {
        if (options.identityFiles.isEmpty()) return
        privateDirectory()
        AetherIdentityStore(directory).ensure(options, { checkCurrent(token) }, forceRenew) { staging ->
            runRegistration(options, token, upstreamHttpPort, staging)
        }
    }

    private fun runRegistration(options: AetherOptions, token: Long, upstreamHttpPort: Int, staging: File) {
        onProgress("registering")
        var args = options.arguments(staging, socksPort, psiphonPort, protectedUpstreamPort, registerOnly = true)
        if (upstreamHttpPort != 0) {
            val at = args.indexOf("--upstream")
            if (at >= 0) args = args.filterIndexed { index, _ -> index != at && index != at + 1 }
            args = args + listOf("--upstream", "http://127.0.0.1:$upstreamHttpPort")
        }
        val process = launch(options, args, token)
        try {
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(options.startupTimeoutSeconds.toLong())
            while (process.isAlive && System.nanoTime() < deadline) {
                checkCurrent(token)
                process.waitFor(150, TimeUnit.MILLISECONDS)
            }
            checkCurrent(token)
            check(!process.isAlive && process.exitValue() == 0 &&
                options.identityFiles.all { File(staging, it).isFile }) {
                "Secure WARP registration failed. Existing identities were retained; retry via an available VPN or another network"
            }
        } finally { owner.finish(token) }
    }

    private fun privateDirectory() {
        check(directory.isDirectory || directory.mkdirs()) { "Could not create private Aether storage" }
        Os.chmod(directory.absolutePath, 448) // 0700, excluded from Android backup by noBackupFilesDir.
    }

    private fun launch(options: AetherOptions, arguments: List<String>, token: Long): Process {
        checkCurrent(token)
        privateDirectory()
        val files = runtimeFiles(options)
        val marker = "NIRANG_AETHER_SESSION=" + UUID.randomUUID().toString()
        val builder = ProcessBuilder(listOf(files.first.absolutePath) + arguments)
            .directory(directory).redirectErrorStream(true)
        builder.environment().apply {
            clear() // No inherited AETHER_* values can alter TLS, files, routing or child programs.
            put("PATH", "/system/bin")
            put("HOME", directory.absolutePath)
            put("TMPDIR", app.cacheDir.absolutePath)
            put("SSL_CERT_FILE", platformCaBundle().absolutePath)
            put("AETHER_TLS_VERIFY", "1")
            put("AETHER_PSIPHON_BIN", files.second.absolutePath)
            put("AETHER_PSIPHON_DIR", File(directory, "psiphon").absolutePath)
            if (options.psiphon != "off") put("AETHER_PSIPHON_SERVER_ENTRIES", bootstrapEntries().absolutePath)
            put(marker.substringBefore('='), marker.substringAfter('='))
        }
        val process = builder.start()
        if (!owner.install(token) { terminate(process, marker) }) throw CancellationException("Aether start cancelled")
        live = process
        process.outputStream.close()
        // Never log raw native output: only strict numeric endpoint results are public status.
        Thread({ runCatching { process.inputStream.bufferedReader().useLines { lines ->
            lines.forEach { line ->
                if (owner.current(token) && live === process) {
                    AetherEndpoint.parse(options.mode,line)?.let { path -> selectedPath=path;onEndpoint(path) }
                }
            }
        } } }, "aether-output").apply { isDaemon = true; start() }
        return process
    }

    private fun runtimeFiles(options: AetherOptions): Pair<File, File> {
        val native = File(app.applicationInfo.nativeLibraryDir)
        val aether = File(native, "libaether_nira.so")
        val psiphon = File(native, "libpsiphon_nira.so")
        val manifest = try { app.assets.open("aether-runtime.json").bufferedReader().use { JSONObject(it.readText()) } }
            catch (_: Exception) { throw IllegalStateException("The secure Aether runtime is not packaged in this build") }
        check(manifest.optString("securityPatch") == "nira-https-peer-v1") { "Aether TLS security patch is required" }
        val abis = manifest.getJSONObject("abis")
        val abi = AetherRuntimeAbi.choose(android.os.Process.is64Bit(), Build.SUPPORTED_32_BIT_ABIS.toList(),
            Build.SUPPORTED_64_BIT_ABIS.toList(), abis.keys().asSequence().toSet())
            ?: throw IllegalStateException("Aether is not supported on this device ABI")
        val hashes = abis.getJSONObject(abi)
        fun verify(file: File, key: String) {
            check(file.isFile && file.canExecute()) { "A required Aether native executable is missing" }
            val digest = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input -> val block = ByteArray(32768)
                while (true) { val count = input.read(block); if (count < 0) break; digest.update(block, 0, count) }
            }
            val actual = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
            check(actual == hashes.getString(key)) { "Aether native executable integrity check failed" }
        }
        verify(aether, "aetherSha256")
        if (options.psiphon != "off") verify(psiphon, "psiphonSha256")
        return aether to psiphon
    }

    private fun bootstrapEntries(): File {
        val manifest = app.assets.open("aether-runtime.json").bufferedReader().use { JSONObject(it.readText()) }
        val expected = manifest.getString("serverEntriesSha256")
        check(expected.matches(Regex("[a-f0-9]{64}"))) { "Invalid Psiphon bootstrap manifest" }
        val target = File(directory, "psiphon-entries-$expected.dat")
        if (!target.isFile) {
            val bytes = app.assets.open("aether-psiphon-server-entries.dat").use { it.readBounded(4 * 1024 * 1024) }
            val actual = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
            check(actual == expected) { "Psiphon bootstrap integrity check failed" }
            val temporary = File(directory, ".psiphon-entries.tmp")
            temporary.writeBytes(bytes)
            Os.chmod(temporary.absolutePath, 384) // 0600
            java.nio.file.Files.move(temporary.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
        return target
    }

    private fun platformCaBundle(): File {
        val factory = javax.net.ssl.TrustManagerFactory.getInstance(javax.net.ssl.TrustManagerFactory.getDefaultAlgorithm())
        factory.init(null as java.security.KeyStore?)
        val manager = factory.trustManagers.filterIsInstance<javax.net.ssl.X509TrustManager>().firstOrNull()
            ?: throw IllegalStateException("Android platform trust manager is unavailable")
        val bytes = AetherCaBundle.encode(manager.acceptedIssuers.map { it.encoded })
        val target = File(directory, "platform-ca.pem")
        if (!target.isFile || !target.readBytes().contentEquals(bytes)) {
            val temporary = File(directory, ".platform-ca.tmp")
            temporary.writeBytes(bytes)
            Os.chmod(temporary.absolutePath, 384)
            java.nio.file.Files.move(temporary.toPath(), target.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                java.nio.file.StandardCopyOption.ATOMIC_MOVE)
        }
        return target
    }

    private fun localListenerReady(): Boolean = runCatching {
        Socket().use { it.connect(InetSocketAddress("127.0.0.1",outputSocksPort),300) }
        true
    }.getOrDefault(false)

    private fun probe(requireWarp: Boolean): Boolean = runCatching {
        val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", outputSocksPort))
        Socket(proxy).use { socket ->
            socket.soTimeout = 3000
            socket.connect(InetSocketAddress.createUnresolved("www.cloudflare.com", 443), 2000)
            ((SSLSocketFactory.getDefault() as SSLSocketFactory).createSocket(socket, "www.cloudflare.com", 443, true) as SSLSocket).use { tls ->
                tls.soTimeout = 3000
                tls.sslParameters = tls.sslParameters.apply { endpointIdentificationAlgorithm = "HTTPS" }
                tls.startHandshake()
                tls.outputStream.write("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n".toByteArray(Charsets.US_ASCII))
                val reply = tls.inputStream.readBounded(16384).toString(Charsets.UTF_8)
                (reply.startsWith("HTTP/1.1 200 ") || reply.startsWith("HTTP/1.0 200 ")) &&
                    reply.contains("\r\n\r\n") && (!requireWarp || reply.contains("warp=on"))
            }
        }
    }.getOrDefault(false)

    private fun checkCurrent(token: Long) {
        if (!owner.current(token) || Thread.currentThread().isInterrupted) throw CancellationException("Aether operation cancelled")
    }

    fun stop() { ready = false; owner.stop(); live = null }
    fun isRunning(): Boolean = ready && live?.isAlive == true

    private fun terminate(process: Process, marker: String) {
        fun markedPids(): List<Int> = File("/proc").listFiles().orEmpty().mapNotNull { path ->
            val pid = path.name.toIntOrNull() ?: return@mapNotNull null
            if (pid == android.os.Process.myPid()) return@mapNotNull null
            val environment = runCatching { File(path, "environ").inputStream().use { it.readBounded(16384) }.toString(Charsets.UTF_8) }.getOrNull()
            pid.takeIf { environment?.split('\u0000')?.contains(marker) == true }
        }
        // Children inherit the unguessable per-operation marker, including the separate Psiphon client.
        markedPids().forEach { pid -> runCatching { Os.kill(pid, OsConstants.SIGTERM) } }
        process.destroy()
        runCatching { process.waitFor(350, TimeUnit.MILLISECONDS) }
        markedPids().forEach { pid -> runCatching { Os.kill(pid, OsConstants.SIGKILL) } }
        if (process.isAlive) process.destroyForcibly()
        if (live === process) live = null
    }

    private fun java.io.InputStream.readBounded(limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val block = ByteArray(2048)
        while (output.size() < limit) {
            val count = read(block, 0, minOf(block.size, limit - output.size()))
            if (count < 0) break
            output.write(block, 0, count)
        }
        return output.toByteArray()
    }
}
