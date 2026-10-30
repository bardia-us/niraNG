package dev.nirang.client.cores.singbox

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.ParcelFileDescriptor
import android.os.Process
import android.system.OsConstants
import io.nekohasekai.libbox.*
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.NetworkInterface as JavaNetworkInterface
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Implements the pinned libbox platform contract; no root, shell, shared files, or TCP control API. */
internal class SingBoxPlatform(
    private val context: Context,
    private val assertCurrent: () -> Unit,
    private val probeOnly: Boolean = false,
) : PlatformInterface, AutoCloseable {
    private val vpn: VpnService? get() = context as? VpnService
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private val closed = AtomicBoolean()
    private val networkReady = CountDownLatch(1)
    private val thread = HandlerThread("nira-singbox-network")
    private val guard = Any()
    @Volatile private var listener: InterfaceUpdateListener? = null
    @Volatile private var network: Network? = null
    private var registered = false
    private var tunnel: ParcelFileDescriptor? = null

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = update(network)
        override fun onLost(network: Network) { if (this@SingBoxPlatform.network == network) update(null) }
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) { if (this@SingBoxPlatform.network == network) update(network) }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) { if (this@SingBoxPlatform.network == network) update(network) }
    }

    fun prepareNetwork() {
        assertCurrent()
        thread.start()
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .build()
        val handler = Handler(thread.looper)
        synchronized(guard) {
            check(!closed.get())
            when {
                Build.VERSION.SDK_INT >= 31 -> connectivity.registerBestMatchingNetworkCallback(request, callback, handler)
                Build.VERSION.SDK_INT >= 28 -> connectivity.requestNetwork(request, callback, handler)
                Build.VERSION.SDK_INT >= 26 -> connectivity.registerDefaultNetworkCallback(callback, handler)
                else -> connectivity.registerDefaultNetworkCallback(callback)
            }
            registered = true
        }
        val active = connectivity.activeNetwork
        if (active != null && isPhysical(active)) update(active)
        check(networkReady.await(5, TimeUnit.SECONDS) && network != null) { "No physical Android network is available" }
        assertCurrent()
    }

    private fun isPhysical(candidate: Network): Boolean {
        val capabilities = connectivity.getNetworkCapabilities(candidate) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) && !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    private fun update(candidate: Network?) {
        synchronized(guard) {
            if (closed.get()) return
            if (candidate != null && !isPhysical(candidate)) return
            network = candidate
            if (candidate != null && connectivity.getLinkProperties(candidate)?.interfaceName?.let {
                    runCatching { JavaNetworkInterface.getByName(it)?.index }.getOrNull()
                } != null) networkReady.countDown()
            if (!probeOnly) vpn?.setUnderlyingNetworks(candidate?.let { arrayOf(it) })
        }
        publish()
    }

    fun hasTunnel(): Boolean = synchronized(guard) { tunnel != null && !closed.get() }

    private fun publish() {
        if (closed.get()) return
        val callback = listener ?: return
        val current = network
        val properties = current?.let(connectivity::getLinkProperties)
        val name = properties?.interfaceName
        val index = name?.let { runCatching { JavaNetworkInterface.getByName(it)?.index }.getOrNull() }
        if (name == null || index == null) {
            callback.updateDefaultInterface("", -1, false, false)
        } else {
            val capabilities = connectivity.getNetworkCapabilities(current)
            val metered = capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) != true
            callback.updateDefaultInterface(name, index, metered, false)
        }
    }

    override fun usePlatformAutoDetectInterfaceControl() = true
    override fun autoDetectInterfaceControl(fd: Int) {
        if (probeOnly) {
            assertCurrent()
            check(!closed.get()) { "Probe session has closed" }
            val upstream = network ?: error("No physical Android network")
            ParcelFileDescriptor.fromFd(fd).use { upstream.bindSocket(it.fileDescriptor) }
            return
        }
        SingBoxSocketProtection.protect(fd, {
            assertCurrent()
            check(!closed.get()) { "sing-box session has closed" }
        }, { descriptor -> vpn?.protect(descriptor) == true })
    }

    override fun openTun(options: TunOptions): Int = synchronized(guard) {
        check(!probeOnly) { "Latency probes cannot open an Android TUN" }
        val vpn = checkNotNull(vpn)
        assertCurrent()
        check(!closed.get() && tunnel == null) { "sing-box TUN session is unavailable" }
        check(VpnService.prepare(vpn) == null) { "Android VPN permission is missing" }
        check(options.autoRoute && !options.isHTTPProxyEnabled) { "Unsupported Android TUN options" }
        val builder = vpn.Builder().setSession("niraNG sing-box").setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= 29) builder.setMetered(false)
        forEach(options.inet4Address) { builder.addAddress(it.address(), it.prefix()) }
        forEach(options.inet6Address) { builder.addAddress(it.address(), it.prefix()) }
        // libbox already computed the exact include-minus-exclude routes for Android API 24+.
        forEach(options.inet4RouteRange) { builder.addRoute(it.address(), it.prefix()) }
        forEach(options.inet6RouteRange) { builder.addRoute(it.address(), it.prefix()) }
        if (options.dnsMode.value != Libbox.DNSModeDisabled) {
            val dns = options.dnsServerAddress
            while (dns.hasNext()) builder.addDnsServer(dns.next())
        }
        val rules = SingBoxAppPolicy.resolve(readStrings(options.includePackage), readStrings(options.excludePackage), vpn.packageName)
        for (name in rules.allowed) builder.addAllowedApplication(name)
        for (name in rules.disallowed) builder.addDisallowedApplication(name)
        val descriptor = builder.establish() ?: error("Android could not establish the sing-box TUN")
        try {
            assertCurrent()
            check(!closed.get())
            tunnel = descriptor
            descriptor.fd // libbox duplicates this FD; platform keeps the original until close.
        } catch (failure: Throwable) {
            descriptor.close()
            throw failure
        }
    }

    private fun forEach(iterator: RoutePrefixIterator, action: (RoutePrefix) -> Unit) {
        while (iterator.hasNext()) action(iterator.next())
    }

    private fun readStrings(iterator: StringIterator): Set<String> = buildSet {
        while (iterator.hasNext()) add(iterator.next())
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) { this.listener = listener; publish() }
    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) { this.listener = null }
    override fun getInterfaces(): NetworkInterfaceIterator {
        val result = connectivity.allNetworks.mapNotNull { candidate ->
            if (!isPhysical(candidate)) return@mapNotNull null
            val properties = connectivity.getLinkProperties(candidate) ?: return@mapNotNull null
            val capabilities = connectivity.getNetworkCapabilities(candidate) ?: return@mapNotNull null
            val name = properties.interfaceName ?: return@mapNotNull null
            val java = JavaNetworkInterface.getByName(name) ?: return@mapNotNull null
            io.nekohasekai.libbox.NetworkInterface().apply {
                this.name = name
                index = java.index
                mtu = java.mtu
                addresses = strings(properties.linkAddresses.map { "${it.address.hostAddress?.substringBefore('%')}/${it.prefixLength}" })
                dnsServer = strings(properties.dnsServers.mapNotNull { it.hostAddress?.substringBefore('%') })
                gateway = strings(properties.routes.filter { it.isDefaultRoute }.mapNotNull { it.gateway?.hostAddress?.substringBefore('%') })
                flags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                if (java.supportsMulticast()) flags = flags or OsConstants.IFF_MULTICAST
                if (java.isPointToPoint) flags = flags or OsConstants.IFF_POINTOPOINT
                type = when {
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                metered = !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
        }.iterator()
        return object : NetworkInterfaceIterator {
            override fun hasNext() = result.hasNext()
            override fun next() = result.next()
        }
    }

    override fun localDNSTransport(): LocalDNSTransport = object : LocalDNSTransport {
        override fun raw() = false
        override fun exchange(context: ExchangeContext, message: ByteArray) { error("Raw local DNS is unavailable") }
        override fun lookup(context: ExchangeContext, family: String, domain: String) {
            assertCurrent()
            val upstream = network ?: error("No physical Android DNS network")
            val addresses = upstream.getAllByName(domain).filter {
                when (family) { "ip4" -> it is Inet4Address; "ip6" -> it is Inet6Address; else -> true }
            }
            context.success(addresses.mapNotNull { it.hostAddress }.joinToString("\n"))
        }
    }

    override fun findConnectionOwner(protocol: Int, source: String, sourcePort: Int, destination: String, destinationPort: Int): ConnectionOwner {
        val owner = if (Build.VERSION.SDK_INT >= 29) {
            val uid = connectivity.getConnectionOwnerUid(protocol, InetSocketAddress(source, sourcePort), InetSocketAddress(destination, destinationPort))
            check(uid != Process.INVALID_UID) { "Connection owner unavailable" }
            ConnectionOwner().apply { userId = uid }
        } else Libbox.findConnectionOwner(protocol, source, sourcePort, destination, destinationPort)
        val packages = context.packageManager.getPackagesForUid(owner.userId)?.toList().orEmpty()
        owner.userName = packages.firstOrNull().orEmpty()
        owner.setAndroidPackageNames(strings(packages))
        return owner
    }

    override fun underNetworkExtension() = false
    override fun includeAllNetworks() = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() = Unit
    override fun registerMyInterface(name: String) = Unit
    override fun sendNotification(notification: Notification) { error("Native notifications are unavailable") }
    override fun cancelNotification(identifier: String, typeID: Int) = Unit
    override fun startNeighborMonitor(listener: NeighborUpdateListener) { error("Neighbor monitoring requires privileges") }
    override fun closeNeighborMonitor(listener: NeighborUpdateListener) = Unit
    override fun usePlatformShell() = false
    override fun checkPlatformShell() { error("Native shell is disabled") }
    override fun openShellSession(user: PlatformUser, command: String, environ: StringIterator, term: String, rows: Int, cols: Int): ShellSession = error("Native shell is disabled")
    override fun lookupUser(username: String): PlatformUser = error("Native users are disabled")
    override fun lookupSFTPServer(): String = error("SFTP is disabled")
    override fun readSystemSSHHostKey(): String = error("Native SSH keys are disabled")
    override fun tailscaleHostname() = ""
    override fun usePlatformBridge() = false
    override fun createBridge(options: BridgeOptions): BridgeSession = error("Native bridges are disabled")

    override fun close() {
        if (!closed.compareAndSet(false, true)) return
        listener = null
        synchronized(guard) {
            if (registered) runCatching { connectivity.unregisterNetworkCallback(callback) }
            registered = false
            runCatching { tunnel?.close() }
            tunnel = null
        }
        network = null
        thread.quitSafely()
    }

    private fun strings(items: List<String>): StringIterator {
        val iterator = items.iterator()
        return object : StringIterator {
            override fun hasNext() = iterator.hasNext()
            override fun next() = iterator.next()
            override fun len() = items.size
        }
    }
}
