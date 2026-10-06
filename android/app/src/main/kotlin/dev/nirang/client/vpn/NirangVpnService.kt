package dev.nirang.client.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import dev.nirang.client.MainActivity
import dev.nirang.client.R
import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.model.ServerEligibility
import dev.nirang.client.network.ProxyIpChecker
import dev.nirang.client.ping.PingManager
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.xray.XrayConfigBuilder
import dev.nirang.client.xray.XrayCore
import dev.nirang.client.xray.IranCidrRepository
import java.net.InetAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class NirangVpnService : VpnService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = VpnTaskRunner()
    private val coreStopWorker = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "nirang-core-stop").apply { isDaemon = true }
    }
    private val startGuard = AtomicBoolean(false)
    private val foregroundActive = AtomicBoolean(false)
    private val operationGate = ConnectionOperationGate()
    private data class PublicIpRequest(val providerUrl: String, val serverId: String, val operation: Long)
    private val publicIpRefreshGate = PublicIpRefreshGate<PublicIpRequest>(SystemClock::elapsedRealtime)
    private val connectionListener: (ConnectionSnapshot) -> Unit = { snapshot ->
        mainHandler.post {
            if (NotificationControlPolicy.shouldUpdateNotification(
                    foregroundActive.get(), snapshot.state, ConnectionStore.state(),
                )) updateNotification(snapshot)
            NirangTileService.requestRefresh(applicationContext)
        }
    }
    private var vpnInterface: ParcelFileDescriptor? = null
    private var currentConfig: String? = null
    @Volatile private var currentServerId: String? = null
    private var currentServerName: String? = null
    private var currentMode: String = "vpn"
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var activeNetwork: Network? = null
    @Volatile private var networkWasLost = false
    private val underlyingNetworks = UnderlyingNetworkTracker<Network>()

    override fun onCreate() {
        super.onCreate()
        SafeLog.initialize(this)
        ensureNotificationChannel()
        liveInstance = this
        ConnectionStore.addListener(connectionListener)
        if (
            !XrayCore.isRunning() &&
            ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.RESTARTING, ConnectionState.ERROR)
        ) {
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        runCatching {
        when (intent?.action) {
            ACTION_STOP -> stopImmediately(false)
            ACTION_STOP_PRESERVING_ERROR -> stopImmediately(true)
            ACTION_STOP_FOR_RESTART -> {
                val operation = operationGate.cancel()
                val generation = intent.getLongExtra(EXTRA_RESTART_GENERATION, 0L)
                val serverId = intent.getStringExtra(EXTRA_SERVER_ID)
                val serverName = intent.getStringExtra(EXTRA_SERVER_NAME)
                submit { stopForRestartInternal(generation, serverId, serverName, operation) }
            }
            ACTION_START -> {
                if (
                    ConnectionStore.state() in setOf(
                        ConnectionState.CONNECTED,
                        ConnectionState.PREPARING,
                        ConnectionState.CONNECTING,
                        ConnectionState.SWITCHING,
                        ConnectionState.RECONNECTING,
                        ConnectionState.STOPPING,
                    )
                ) {
                    return@runCatching
                }
                val operation = operationGate.begin()
                val serverId = intent.getStringExtra(EXTRA_SERVER_ID)
                val selected = SubscriptionRepository(this).run {
                    serverId?.let(::server) ?: selectedServer()
                }
                ConnectionStore.transition(ConnectionState.PREPARING, selected?.id, selected?.name)
                foregroundActive.set(true)
                startForeground(NOTIFICATION_ID, buildNotification(ConnectionStore.current()))
                val allowFallback = intent.getBooleanExtra(EXTRA_ALLOW_FALLBACK, true)
                submit { startInternal(serverId, allowFallback, operation) }
            }
            ACTION_SWITCH -> intent.getStringExtra(EXTRA_SERVER_ID)?.let {
                VpnRestartCoordinator.request(applicationContext, it)
            }
        }
        }.onFailure(::handleLifecycleFailure)
        return START_NOT_STICKY
    }

    override fun onRevoke() {
        SafeLog.warning(this, "VPN permission revoked")
        stopImmediately(false)
    }

    override fun onDestroy() {
        if (liveInstance === this) liveInstance = null
        publicIpRefreshGate.invalidate()
        operationGate.cancel()
        foregroundActive.set(false)
        removeForegroundNotification()
        ConnectionStore.removeListener(connectionListener)
        closeTunnelAndCallbacks()
        stopCoreAsync()
        if (ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.RESTARTING, ConnectionState.ERROR)) {
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
        }
        NirangTileService.requestRefresh(applicationContext)
        worker.shutdownNow()
        coreStopWorker.shutdown()
        super.onDestroy()
    }

    private fun startInternal(requestedServerId: String?, allowFallback: Boolean, operation: Long) {
        if (!startGuard.compareAndSet(false, true)) return
        if (!operationGate.isCurrent(operation)) {
            startGuard.set(false)
            return
        }
        if (ConnectionStore.state() in setOf(ConnectionState.CONNECTING, ConnectionState.CONNECTED, ConnectionState.SWITCHING, ConnectionState.RECONNECTING)) {
            startGuard.set(false)
            return
        }
        val repository = SubscriptionRepository(this)
        val server = requestedServerId?.let(repository::server) ?: repository.selectedServer()
        if (server == null) {
            failAndStop("No server is available")
            return
        }
        ServerEligibility.rejectionReason(server)?.let { reason ->
            failAndStop(reason)
            return
        }
        repository.select(server.id)
        currentServerId = server.id
        currentServerName = server.name
        ConnectionStore.transition(ConnectionState.PREPARING, server.id, server.name)
        SafeLog.info(this, "Server selected")
        val settings = NativeSettings(this)
        currentMode = settings.connectionMode

        try {
            val iranCidrs = routingCidrs(settings)
            if (currentMode == "vpn" && prepare(this) != null) error("VPN permission is not granted")
            currentConfig = if (currentMode == "vpn") {
                XrayConfigBuilder.buildVpnConfig(server, settings, iranCidrs)
            } else {
                XrayConfigBuilder.buildProxyConfig(server, settings, iranCidrs)
            }
            vpnInterface = if (currentMode == "vpn") {
                buildVpnInterface(server.name, settings) ?: error("Android could not establish the VPN interface")
            } else {
                null
            }
            check(operationGate.isCurrent(operation)) { CANCELLED_OPERATION }
            ConnectionStore.transition(ConnectionState.CONNECTING, server.id, server.name)
            XrayCore.start(this, currentConfig!!, vpnInterface?.fd ?: 0)
            if (!operationGate.isCurrent(operation)) {
                cleanupResources()
                return
            }
            registerNetworkCallback(operation)
            ConnectionStore.transition(ConnectionState.CONNECTED, server.id, server.name)
            markLastWorking(server.id)
            SafeLog.info(this, "VPN started")
            SafeLog.info(this, "Xray started")
            requestPublicIpRefresh(settings.ipCheckUrl, server.id, operation)
            refreshConnectedServerPing(repository, server.id)
        } catch (error: Throwable) {
            if (!operationGate.isCurrent(operation) || error.message == CANCELLED_OPERATION) {
                cleanupResources()
                return
            }
            if (allowFallback && tryStartLastWorkingServer(settings, repository, operation)) return
            failAndStop(error.message ?: "Connection failed")
            return
        } finally {
            startGuard.set(false)
        }
    }

    private fun tryStartLastWorkingServer(
        settings: NativeSettings,
        repository: SubscriptionRepository,
        operation: Long,
    ): Boolean {
        if (!operationGate.isCurrent(operation)) return false
        val fallbackId = runCatching {
            getSharedPreferences(VPN_STATE_PREFS, MODE_PRIVATE).getString(LAST_WORKING_SERVER_ID, null)
        }.getOrNull() ?: return false
        val fallback = repository.server(fallbackId) ?: return false
        val fd = vpnInterface?.fd ?: if (currentMode == "proxy") 0 else return false
        return runCatching {
            XrayCore.stop()
            check(operationGate.isCurrent(operation)) { CANCELLED_OPERATION }
            val fallbackConfig = if (currentMode == "vpn") {
                XrayConfigBuilder.buildSafeFallbackConfig(fallback)
            } else {
                XrayConfigBuilder.buildProxyConfig(fallback, settings, routingCidrs(settings))
            }
            ConnectionStore.transition(ConnectionState.CONNECTING, fallback.id, fallback.name)
            XrayCore.start(this, fallbackConfig, fd)
            if (!operationGate.isCurrent(operation)) {
                XrayCore.stop()
                return@runCatching false
            }
            currentServerId = fallback.id
            currentServerName = fallback.name
            currentConfig = fallbackConfig
            repository.select(fallback.id)
            NativeEvents.emit("servers", repository.safeServers())
            NativeSettings(this).also { safeSettings ->
                safeSettings.resetNetworkToSafeDefaults()
                NativeEvents.emit("settings", safeSettings.toMap())
            }
            registerNetworkCallback(operation)
            ConnectionStore.transition(
                ConnectionState.CONNECTED,
                fallback.id,
                fallback.name,
                "Selected configuration failed; safe network settings restored",
            )
            SafeLog.warning(this, "Previous working server restored")
            requestPublicIpRefresh(settings.ipCheckUrl, fallback.id, operation)
            refreshConnectedServerPing(repository, fallback.id)
            true
        }.getOrElse { false }
    }

    private fun markLastWorking(serverId: String) {
        getSharedPreferences(VPN_STATE_PREFS, MODE_PRIVATE)
            .edit().putString(LAST_WORKING_SERVER_ID, serverId).apply()
    }

    private fun refreshConnectedServerPing(repository: SubscriptionRepository, serverId: String) {
        lateinit var manager: PingManager
        manager = PingManager(applicationContext, repository)
        manager.testSingle(serverId) { manager.close() }
    }

    private fun buildVpnInterface(serverName: String, settings: NativeSettings): ParcelFileDescriptor? {
        val addressParts = settings.vpnInterfaceAddress.split('/', limit = 2)
        val interfaceAddress = addressParts[0]
        val interfacePrefix = addressParts[1].toInt()
        val builder = Builder()
            .setSession("niraNG · $serverName")
            .setMtu(settings.vpnMtu)
            .addAddress(interfaceAddress, interfacePrefix)
            .addRoute("0.0.0.0", 0)
            .setBlocking(true)
        applyPerAppPolicy(builder, settings)
        if (settings.enableIpv6) {
            builder
                .addAddress("fdfe:dcba:9877::1", 126)
                .addRoute("::", 0)
        }
        resolveVpnDns(settings)?.let { builder.addDnsServer(it) }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
            if (settings.addHttpProxyToVpn) {
                builder.setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", XrayConfigBuilder.LOCAL_HTTP_PROXY_PORT))
            }
        }
        return builder.establish()
    }

    private fun applyPerAppPolicy(builder: Builder, settings: NativeSettings) {
        val installedPackages = settings.perAppPackages.filter { candidate ->
            runCatching {
                packageManager.getApplicationInfo(candidate, 0)
            }.isSuccess
        }.toSet()
        val rules = PerAppPolicy.resolve(
            settings.perAppMode,
            settings.perAppPackages,
            installedPackages,
            packageName,
        )
        rules.allowed.forEach { candidate ->
            runCatching { builder.addAllowedApplication(candidate) }
        }
        rules.disallowed.forEach { candidate ->
            runCatching { builder.addDisallowedApplication(candidate) }
        }
        if (rules.fellBackToAllApps) {
            // Android has no "route no apps" builder mode. Keep the VPN usable
            // if every selected application was uninstalled.
            SafeLog.warning(this, "Per-app selection is empty; using all installed apps")
        }
    }

    private fun resolveVpnDns(settings: NativeSettings): InetAddress? {
        runCatching { return InetAddress.getByName(settings.vpnDns) }
        val manager = getSystemService(ConnectivityManager::class.java)
        val systemDns = manager?.activeNetwork?.let { manager.getLinkProperties(it) }?.dnsServers?.firstOrNull()
        return systemDns ?: runCatching { InetAddress.getByName("1.1.1.1") }.getOrNull()
    }

    private fun registerNetworkCallback(operation: Long) {
        unregisterNetworkCallback()
        val manager = getSystemService(ConnectivityManager::class.java) ?: return
        connectivityManager = manager
        networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                if (networkCallback !== this || !operationGate.isCurrent(operation)) return
                if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return
                val selected = underlyingNetworks.update(
                    network,
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
                )
                updateUnderlyingNetwork(selected, operation)
            }

            override fun onLost(network: Network) {
                if (networkCallback !== this || !operationGate.isCurrent(operation)) return
                updateUnderlyingNetwork(underlyingNetworks.remove(network), operation)
            }
        }
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
        manager.registerNetworkCallback(request, networkCallback!!)
    }

    private fun updateUnderlyingNetwork(network: Network?, operation: Long) {
        if (!operationGate.isCurrent(operation)) return
        val previous = activeNetwork
        if (previous != network) publicIpRefreshGate.invalidate()
        activeNetwork = network
        runCatching { setUnderlyingNetworks(network?.let { arrayOf(it) } ?: emptyArray()) }
        val state = ConnectionStore.state()
        if (previous != network && (previous != null || state == ConnectionState.RECONNECTING)) {
            networkWasLost = true
            if (state == ConnectionState.CONNECTED) {
                ConnectionStore.transition(ConnectionState.RECONNECTING, currentServerId, currentServerName)
            }
            SafeLog.info(this, "Underlying network changed")
        }
        if (network != null && networkWasLost && ConnectionStore.state() == ConnectionState.RECONNECTING) {
            val candidate = underlyingNetworks.snapshot()
            if (candidate.network != network) return
            networkWasLost = false
            submit { reconnectCore(operation, candidate) }
        } else if (previous == null && network != null && state == ConnectionState.CONNECTED) {
            currentServerId?.let { requestPublicIpRefresh(NativeSettings(this).ipCheckUrl, it, operation) }
        }
    }

    private fun reconnectCore(operation: Long, candidate: UnderlyingNetworkTracker.Snapshot<Network>) {
        if (!operationGate.isCurrent(operation) || !underlyingNetworks.isCurrent(candidate)) return
        val config = currentConfig ?: return
        val fd = vpnInterface?.fd ?: if (currentMode == "proxy") 0 else return
        val delays = longArrayOf(500L, 1_500L, 3_000L)
        for (delay in delays) {
            if (!operationGate.isCurrent(operation) || !underlyingNetworks.isCurrent(candidate)) return
            try {
                XrayCore.stop()
                Thread.sleep(delay)
                if (!operationGate.isCurrent(operation) || !underlyingNetworks.isCurrent(candidate)) return
                XrayCore.start(this, config, fd)
                if (!operationGate.isCurrent(operation) || !underlyingNetworks.isCurrent(candidate)) {
                    XrayCore.stop()
                    return
                }
                val completed = underlyingNetworks.completeReconnect(candidate) {
                    if (operationGate.isCurrent(operation)) {
                        ConnectionStore.transition(ConnectionState.CONNECTED, currentServerId, currentServerName)
                    }
                }
                if (!completed || !operationGate.isCurrent(operation)) {
                    XrayCore.stop()
                    return
                }
                SafeLog.info(this, "VPN reconnected")
                currentServerId?.let { requestPublicIpRefresh(NativeSettings(this).ipCheckUrl, it, operation) }
                return
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return
            } catch (_: Throwable) {
                // Continue with bounded exponential backoff.
            }
        }
        if (!operationGate.isCurrent(operation) || !underlyingNetworks.isCurrent(candidate)) return
        failAndStop("Unable to reconnect after network change")
    }

    private fun requestPublicIpRefresh(
        providerUrl: String,
        expectedServerId: String,
        operation: Long,
        manual: Boolean = false,
    ): Boolean {
        if (!operationGate.isCurrent(operation) || currentServerId != expectedServerId ||
            ConnectionStore.state() != ConnectionState.CONNECTED) return false
        val request = publicIpRefreshGate.tryBegin(
            manual,
            PublicIpRequest(providerUrl, expectedServerId, operation),
        ) ?: return false
        return dispatchPublicIpRefresh(request)
    }

    private fun dispatchPublicIpRefresh(request: PublicIpRefreshGate.Request<PublicIpRequest>): Boolean {
        val parameters = request.payload
        if (!publicIpRefreshGate.commitIfCurrent(request) {
                isPublicIpRequestCurrent(parameters) && ConnectionStore.beginPublicIpRefresh(parameters.serverId)
            }) {
            publicIpRefreshGate.abandon(request)?.let(::dispatchPublicIpRefresh)
            return false
        }
        val accepted = submitDiagnostic {
            try {
                refreshPublicIp(request)
            } finally {
                publicIpRefreshGate.complete(request)?.let(::dispatchPublicIpRefresh)
            }
        }
        if (!accepted) {
            publicIpRefreshGate.commitIfCurrent(request) {
                isPublicIpRequestCurrent(parameters) && ConnectionStore.setPublicIp(parameters.serverId, null, null, null)
            }
            publicIpRefreshGate.invalidate()
            publicIpRefreshGate.abandon(request)
        }
        return accepted
    }

    private fun isPublicIpRequestCurrent(request: PublicIpRequest): Boolean =
        operationGate.isCurrent(request.operation) && currentServerId == request.serverId &&
            ConnectionStore.state() == ConnectionState.CONNECTED && !Thread.currentThread().isInterrupted

    private fun refreshPublicIp(request: PublicIpRefreshGate.Request<PublicIpRequest>) {
        val parameters = request.payload
        repeat(PUBLIC_IP_ATTEMPTS) { attempt ->
            if (!publicIpRefreshGate.commitIfCurrent(request) { isPublicIpRequestCurrent(parameters) }) return
            val result = runCatching { ProxyIpChecker.check(parameters.providerUrl) }.getOrNull()
            if (!publicIpRefreshGate.commitIfCurrent(request) { isPublicIpRequestCurrent(parameters) }) return
            if (result?.ip?.isNotBlank() == true) {
                if (publicIpRefreshGate.commitIfCurrent(request) {
                        isPublicIpRequestCurrent(parameters) &&
                            ConnectionStore.setPublicIp(parameters.serverId, result.ip, result.countryCode, result.city)
                    }) {
                    SafeLog.info(this, "Public IP refreshed")
                }
                return
            }
            if (attempt + 1 < PUBLIC_IP_ATTEMPTS) Thread.sleep(PUBLIC_IP_RETRY_DELAY_MS)
        }
        if (publicIpRefreshGate.commitIfCurrent(request) {
                isPublicIpRequestCurrent(parameters) && ConnectionStore.setPublicIp(parameters.serverId, null, null, null)
            }) SafeLog.warning(this, "Public IP check failed")
    }

    private fun routingCidrs(settings: NativeSettings): List<String> =
        if (settings.routingMode == "bypassIran") IranCidrRepository.load(applicationContext) else emptyList()

    private fun failAndStop(message: String) {
        if (ConnectionStore.state() == ConnectionState.DISCONNECTED) return
        val technicalMessage = message
            .replace(Regex("https?://\\S+", RegexOption.IGNORE_CASE), "endpoint")
            .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "identifier")
            .replace(Regex("(?i)(password|credential|uuid|publicKey|shortId|id)\\s*[:=]\\s*[^,}\\s]+"), "$1=[redacted]")
            .replace(Regex("[A-Za-z0-9_+/-]{48,}={0,2}"), "[redacted value]")
            .take(1_200)
        SafeLog.error(this, "Connection error: $technicalMessage")
        ConnectionStore.transition(
            ConnectionState.ERROR,
            currentServerId,
            currentServerName,
            technicalMessage.take(240),
        )
        stopInternal(true)
        startGuard.set(false)
    }

    private fun submit(action: () -> Unit): Boolean = worker.submit {
        runCatching(action).onFailure { error ->
            handleUnexpectedWorkerFailure(error)
        }
    }

    private fun submitDiagnostic(action: () -> Unit): Boolean = worker.submitDiagnostic {
        runCatching(action).onFailure { error ->
            if (error is InterruptedException) Thread.currentThread().interrupt()
            else SafeLog.warning(this, "VPN diagnostic failed: ${error.javaClass.simpleName}")
        }
    }

    private fun handleUnexpectedWorkerFailure(error: Throwable) {
        val message = error.message ?: error.javaClass.simpleName
        SafeLog.error(this, "Unhandled VPN worker failure: ${error.javaClass.simpleName}")
        if (ConnectionStore.state() !in setOf(ConnectionState.DISCONNECTED, ConnectionState.ERROR)) {
            failAndStop(message)
        }
    }

    private fun handleLifecycleFailure(error: Throwable) {
        foregroundActive.set(false)
        SafeLog.error(this, "VPN service lifecycle failure: ${error.javaClass.simpleName}")
        ConnectionStore.transition(ConnectionState.ERROR, currentServerId, currentServerName, "VPN service could not start")
        runCatching { cleanupResources() }
        removeForegroundNotification()
        stopSelf()
    }

    private fun stopInternal(preserveError: Boolean) {
        foregroundActive.set(false)
        operationGate.cancel()
        if (!preserveError) ConnectionStore.transition(ConnectionState.STOPPING, currentServerId, currentServerName)
        cleanupResources()
        if (!preserveError) ConnectionStore.transition(ConnectionState.DISCONNECTED)
        SafeLog.info(this, "VPN stopped")
        removeForegroundNotification()
        stopSelf()
    }

    private fun stopImmediately(preserveError: Boolean) {
        foregroundActive.set(false)
        operationGate.cancel()
        VpnRestartCoordinator.cancel()
        startGuard.set(false)
        if (!preserveError) ConnectionStore.transition(ConnectionState.DISCONNECTED)
        closeTunnelAndCallbacks()
        currentConfig = null
        currentServerId = null
        currentServerName = null
        currentMode = "vpn"
        stopCoreAsync()
        SafeLog.info(this, "VPN stop requested")
        removeForegroundNotification()
        stopSelf()
    }

    private fun stopForRestartInternal(generation: Long, serverId: String?, serverName: String?, operation: Long) {
        if (!operationGate.isCurrent(operation)) return
        foregroundActive.set(false)
        cleanupResources()
        if (!operationGate.isCurrent(operation)) return
        ConnectionStore.transition(ConnectionState.RESTARTING, serverId, serverName)
        SafeLog.info(this, "VPN service stopped for restart")
        removeForegroundNotification()
        VpnRestartCoordinator.onServiceStopped(generation)
        stopSelf()
    }

    private fun cleanupResources() {
        runCatching { XrayCore.stop() }
        runCatching { vpnInterface?.close() }
        vpnInterface = null
        currentConfig = null
        currentServerId = null
        currentServerName = null
        currentMode = "vpn"
        unregisterNetworkCallback()
    }

    private fun closeTunnelAndCallbacks() {
        val tunnel = vpnInterface
        vpnInterface = null
        runCatching { tunnel?.close() }
        unregisterNetworkCallback()
    }

    private fun stopCoreAsync() {
        runCatching {
            coreStopWorker.execute {
                runCatching { XrayCore.stop() }
                    .onFailure { SafeLog.warning(this, "Xray stop did not complete cleanly") }
            }
        }
    }

    private fun unregisterNetworkCallback() {
        publicIpRefreshGate.invalidate()
        networkCallback?.let { callback -> runCatching { connectivityManager?.unregisterNetworkCallback(callback) } }
        networkCallback = null
        connectivityManager = null
        activeNetwork = null
        networkWasLost = false
        underlyingNetworks.clear()
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(CHANNEL_ID, getString(R.string.vpn_channel_name), NotificationManager.IMPORTANCE_LOW).apply {
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
        if (manager.getNotificationChannel(LEGACY_CHANNEL_ID) != null) {
            manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        }
    }

    private fun removeForegroundNotification() {
        val remove = {
            // Serialize removal with listener notifications. A queued worker
            // teardown must not remove a newly started foreground session.
            if (!foregroundActive.get()) {
                runCatching { stopForeground(STOP_FOREGROUND_REMOVE) }
                runCatching { getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID) }
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) remove() else mainHandler.post { remove() }
    }

    private fun updateNotification(snapshot: ConnectionSnapshot) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(snapshot))
    }

    private fun buildNotification(snapshot: ConnectionSnapshot): Notification {
        val status = getString(
            when (snapshot.state) {
                ConnectionState.CONNECTED -> R.string.vpn_connected
                ConnectionState.RECONNECTING -> R.string.vpn_reconnecting
                ConnectionState.STOPPING -> R.string.vpn_stopping
                ConnectionState.ERROR -> R.string.vpn_error
                ConnectionState.DISCONNECTED -> R.string.vpn_disconnected
                else -> R.string.vpn_connecting
            },
        )
        val openIntent = PendingIntent.getActivity(
            this, REQUEST_OPEN_APP, Intent(this, MainActivity::class.java).setAction(ACTION_OPEN_APP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_nirang)
            .setContentTitle("niraNG")
            .setContentText(listOfNotNull(status, snapshot.serverName).joinToString(" · "))
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setBadgeIconType(NotificationCompat.BADGE_ICON_SMALL)
            .setNumber(NotificationControlPolicy.badgeCount(snapshot.state))
        if (NotificationControlPolicy.action(snapshot.state) == NotificationControlAction.DISCONNECT) {
            val disconnectIntent = PendingIntent.getService(
                this,
                REQUEST_DISCONNECT,
                Intent(this, NirangVpnService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            builder.addAction(0, getString(R.string.vpn_disconnect), disconnectIntent)
        }
        return builder.build()
    }

    companion object {
        const val ACTION_START = "dev.nirang.client.action.START_VPN"
        const val ACTION_STOP = "dev.nirang.client.action.STOP_VPN"
        const val ACTION_STOP_PRESERVING_ERROR = "dev.nirang.client.action.STOP_VPN_PRESERVING_ERROR"
        const val ACTION_STOP_FOR_RESTART = "dev.nirang.client.action.STOP_VPN_FOR_RESTART"
        const val ACTION_SWITCH = "dev.nirang.client.action.SWITCH_VPN"
        private const val ACTION_OPEN_APP = "dev.nirang.client.action.OPEN_APP"
        const val EXTRA_SERVER_ID = "serverId"
        const val EXTRA_SERVER_NAME = "serverName"
        const val EXTRA_RESTART_GENERATION = "restartGeneration"
        const val EXTRA_ALLOW_FALLBACK = "allowFallback"
        // Android notification-channel behavior is immutable after creation. The legacy
        // channel explicitly disabled launcher badges, so a new channel is required.
        private const val CHANNEL_ID = "nirang_vpn_status"
        private const val LEGACY_CHANNEL_ID = "nirang_vpn"
        private const val NOTIFICATION_ID = 4107
        private const val REQUEST_OPEN_APP = 41070
        private const val REQUEST_DISCONNECT = 41072
        private const val VPN_STATE_PREFS = "nirang_vpn_state"
        private const val LAST_WORKING_SERVER_ID = "lastWorkingServerId"
        private const val PUBLIC_IP_ATTEMPTS = 3
        private const val PUBLIC_IP_RETRY_DELAY_MS = 700L
        private const val CANCELLED_OPERATION = "Connection operation was cancelled"
        @Volatile private var liveInstance: NirangVpnService? = null

        fun refreshPublicIp(context: Context): Boolean {
            val service = liveInstance ?: return false
            val serverId = service.currentServerId ?: return false
            if (ConnectionStore.state() != ConnectionState.CONNECTED) return false
            return service.requestPublicIpRefresh(
                NativeSettings(context.applicationContext).ipCheckUrl,
                serverId,
                service.operationGate.current(),
                manual = true,
            )
        }

        fun start(context: Context, serverId: String, allowFallback: Boolean = true) {
            val intent = Intent(context, NirangVpnService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SERVER_ID, serverId)
                .putExtra(EXTRA_ALLOW_FALLBACK, allowFallback)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent) else context.startService(intent)
        }

        fun stop(context: Context) {
            VpnRestartCoordinator.cancel()
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
            runCatching {
                context.startService(Intent(context, NirangVpnService::class.java).setAction(ACTION_STOP))
            }.onFailure {
                SafeLog.warning(context, "VPN stop command could not be delivered")
            }
        }

        internal fun stopPreservingError(context: Context) {
            context.startService(
                Intent(context, NirangVpnService::class.java).setAction(ACTION_STOP_PRESERVING_ERROR),
            )
        }

        internal fun stopForRestart(
            context: Context,
            generation: Long,
            serverId: String,
            serverName: String,
        ) {
            context.startService(
                Intent(context, NirangVpnService::class.java)
                    .setAction(ACTION_STOP_FOR_RESTART)
                    .putExtra(EXTRA_RESTART_GENERATION, generation)
                    .putExtra(EXTRA_SERVER_ID, serverId)
                    .putExtra(EXTRA_SERVER_NAME, serverName),
            )
        }

        fun restart(context: Context, serverId: String): Boolean =
            VpnRestartCoordinator.request(context, serverId)

        fun switchServer(context: Context, serverId: String) {
            restart(context, serverId)
        }
    }
}
