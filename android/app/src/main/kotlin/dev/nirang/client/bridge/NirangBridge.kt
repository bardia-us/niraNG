package dev.nirang.client.bridge

import android.app.Activity
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import dev.nirang.client.BuildConfig
import dev.nirang.client.R
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.model.ServerEligibility
import dev.nirang.client.ping.PingManager
import dev.nirang.client.registration.DeviceRegistrationManager
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.subscription.SubscriptionScheduler
import dev.nirang.client.vpn.ConnectionStore
import dev.nirang.client.vpn.NirangVpnService
import dev.nirang.client.vpn.NirangTileService
import dev.nirang.client.vpn.RestartPolicy
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class NirangBridge(
    private val activity: Activity,
    flutterEngine: FlutterEngine,
    private val requestVpnPermission: (String, MethodChannel.Result) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val disposed = AtomicBoolean(false)
    private val repository = SubscriptionRepository(activity.applicationContext)
    private val pingManager = PingManager(activity.applicationContext, repository)
    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(NativeEvents)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceRegistrationStatus" -> {
                val accepted = DeviceRegistrationManager.hasConsent(activity)
                if (accepted) DeviceRegistrationManager.scheduleSync(activity)
                result.success(accepted)
            }
            "acceptDeviceRegistration" -> acceptDeviceRegistration(result)
            "exitApplication" -> {
                activity.finishAndRemoveTask()
                result.success(true)
            }
            "initialize" -> initialize(result)
            "getBootstrap" -> success(result) { bootstrap() }
            "refreshSubscription" -> refreshSubscription(result)
            "selectServer" -> selectServer(call, result)
            "deleteServer" -> deleteServer(call, result)
            "restoreDeletedServers" -> restoreDeletedServers(result)
            "connect" -> connect(call, result)
            "disconnect" -> {
                NirangVpnService.stop(activity)
                result.success(true)
            }
            "restartService" -> restartService(result)
            "requestQuickSettingsTile" -> requestQuickSettingsTile(result)
            "pingServer" -> {
                val id = call.argument<String>("id")
                val server = id?.let(repository::server)
                if (server == null) {
                    result.error("not_found", "Server not found", null)
                } else {
                    pingManager.testSingle(id)
                    result.success(true)
                }
            }
            "pingAll" -> {
                pingManager.testAll()
                result.success(true)
            }
            "cancelPing" -> {
                pingManager.cancel()
                result.success(true)
            }
            "updateSettings" -> updateSettings(call, result)
            "getLogs" -> success(result) { SafeLog.list(activity) }
            "clearLogs" -> success(result) {
                SafeLog.clear(activity)
                true
            }
            "telegramReminderEligible" -> result.success(NativeSettings(activity).telegramReminderEligible())
            "recordTelegramDecision" -> {
                NativeSettings(activity).recordTelegramDecision(call.argument<String>("decision") ?: "later")
                result.success(true)
            }
            "recordFlutterError" -> {
                val message = call.argument<String>("message").orEmpty()
                SafeLog.error(activity, "Flutter error: ${message.take(1_200)}")
                result.success(true)
            }
            "openTelegram" -> openTelegram(result)
            "openExternalUrl" -> openExternalUrl(call, result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        pingManager.close()
        executor.shutdownNow()
    }

    private fun initialize(result: MethodChannel.Result) {
        executor.execute {
            runCatching {
                check(DeviceRegistrationManager.hasConsent(activity)) { "Device registration consent is required" }
                runCatching { activity.deleteSharedPreferences("nirang_traffic") }
                val settings = NativeSettings(activity).also { it.incrementOpenCount() }
                bootstrap().toMutableMap().apply { put("settings", settings.toMap()) }
            }.onSuccess { payload ->
                postToFlutter {
                    result.success(payload)
                }
                runCatching {
                    executor.execute {
                        runCatching { SubscriptionScheduler.reconcile(activity) }
                            .onFailure {
                                SafeLog.warning(activity, "Subscription scheduler unavailable")
                            }
                    }
                }
            }.onFailure { error ->
                SafeLog.error(activity, "Startup initialization failed")
                postToFlutter { result.error("startup", safeError(error), null) }
            }
        }
    }

    private fun requestQuickSettingsTile(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success("manual")
            return
        }
        val manager = activity.getSystemService(StatusBarManager::class.java)
        if (manager == null) {
            result.success("manual")
            return
        }
        manager.requestAddTileService(
            ComponentName(activity, NirangTileService::class.java),
            activity.getString(R.string.quick_tile_label),
            Icon.createWithResource(activity, R.drawable.ic_stat_nirang),
            activity.mainExecutor,
        ) { code ->
            val value = when (code) {
                StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> "already_added"
                StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED -> "requested"
                else -> "manual"
            }
            if (!disposed.get()) result.success(value)
        }
    }

    private fun acceptDeviceRegistration(result: MethodChannel.Result) {
        executor.execute {
            runCatching {
                check(DeviceRegistrationManager.accept(activity)) {
                    "Device registration consent could not be saved"
                }
                true
            }.onSuccess { accepted -> postToFlutter { result.success(accepted) } }
                .onFailure { error ->
                    postToFlutter { result.error("registration", safeError(error), null) }
                }
        }
    }

    private fun refreshSubscription(result: MethodChannel.Result) {
        executor.execute {
            try {
                val snapshot = repository.refresh()
                SafeLog.info(activity, "Subscription updated")
                val data = mapOf(
                    "servers" to repository.safeServers(),
                    "usage" to snapshot.usage.toMap(),
                    "lastUpdated" to snapshot.lastUpdatedEpochMillis,
                    "deletedServerCount" to repository.deletedCount(),
                )
                NativeEvents.emit("subscription", data)
                postToFlutter { result.success(data) }
            } catch (error: Exception) {
                SafeLog.warning(activity, "Subscription update failed")
                postToFlutter { result.error("subscription", safeError(error), null) }
            }
        }
    }

    private fun selectServer(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val server = id?.let(repository::server)
        if (id == null || server == null) {
            result.error("not_found", "Server not found", null)
            return
        }
        val connection = ConnectionStore.snapshot()
        val activeId = connection["serverId"] as? String
        val state = ConnectionStore.state()
        if (activeId != null && activeId != id && state in ACTIVE_CONNECTION_STATES) {
            NirangVpnService.switchServer(activity, server.id)
            SafeLog.info(activity, "Server switch queued")
        } else {
            repository.select(id)
            SafeLog.info(activity, "Server selected")
        }
        // While connected, selection remains on the verified active server.
        // The service emits the new selection only after Xray starts it.
        result.success(repository.safeServers())
    }

    private fun deleteServer(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val activeServerId = ConnectionStore.snapshot()["serverId"] as? String
        if (id != null && id == activeServerId && ConnectionStore.state() != ConnectionState.DISCONNECTED) {
            result.error("busy", "Disconnect this server before deleting it", null)
            return
        }
        if (id == null || !repository.delete(id)) {
            result.error("not_found", "Server not found", null)
            return
        }
        SafeLog.info(activity, "Server hidden locally")
        val servers = repository.safeServers()
        NativeEvents.emit("servers", servers)
        result.success(mapOf("servers" to servers, "deletedServerCount" to repository.deletedCount()))
    }

    private fun restoreDeletedServers(result: MethodChannel.Result) {
        val restored = repository.restoreDeleted()
        val servers = repository.safeServers()
        if (restored > 0) SafeLog.info(activity, "Deleted servers restored")
        NativeEvents.emit("servers", servers)
        result.success(mapOf("servers" to servers, "deletedServerCount" to repository.deletedCount(), "restored" to restored))
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        if (!DeviceRegistrationManager.hasConsent(activity)) {
            result.error("consent_required", "Device registration consent is required", null)
            return
        }
        if (ConnectionStore.state() in ACTIVE_CONNECTION_STATES + ConnectionState.STOPPING) {
            result.error("busy", "A VPN transition is already in progress", null)
            return
        }
        val requested = call.argument<String>("id") ?: repository.selectedServer()?.id
        val server = requested?.let(repository::server)
        if (requested == null || server == null) {
            result.error("no_server", "Select a server first", null)
            return
        }
        ServerEligibility.rejectionReason(server)?.let { reason ->
            result.error("not_connectable", reason, null)
            return
        }
        repository.select(requested)
        requestVpnPermission(requested, result)
    }

    private fun restartService(result: MethodChannel.Result) {
        val snapshot = ConnectionStore.snapshot()
        val serverId = snapshot["serverId"] as? String
        if (ConnectionStore.state() != ConnectionState.CONNECTED || serverId == null) {
            result.error("not_connected", "VPN is not connected", null)
            return
        }
        if (!NirangVpnService.restart(activity, serverId)) {
            result.error("not_found", "Active server is no longer available", null)
            return
        }
        result.success(true)
    }

    private fun updateSettings(call: MethodCall, result: MethodChannel.Result) {
        val values = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        executor.execute {
            runCatching {
                val nativeSettings = NativeSettings(activity)
                val before = nativeSettings.toMap()
                nativeSettings.update(values)
                if (values.containsKey("autoUpdate") || values.containsKey("updateIntervalHours")) {
                    SubscriptionScheduler.reconcile(activity)
                }
                val settings = NativeSettings(activity).toMap()
                val changedKeys = values.keys.mapNotNull { it as? String }
                    .filterTo(mutableSetOf()) { before[it] != settings[it] }
                val connection = ConnectionStore.snapshot()
                val activeId = connection["serverId"] as? String
                if (
                    activeId != null &&
                    RestartPolicy.requiresRestart(changedKeys) &&
                    ConnectionStore.state() in RESTART_ELIGIBLE_STATES
                ) {
                    NirangVpnService.restart(activity, activeId)
                }
                settings
            }.onSuccess { settings ->
                postToFlutter { result.success(settings) }
            }.onFailure { error ->
                SafeLog.warning(activity, "Invalid settings rejected")
                postToFlutter { result.error("invalid_settings", safeError(error), null) }
            }
        }
    }

    private fun openTelegram(result: MethodChannel.Result) {
        if (BuildConfig.TELEGRAM_URL.isBlank()) {
            result.error("not_configured", "Telegram channel is not configured", null)
            return
        }
        runCatching {
            activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.TELEGRAM_URL)))
        }.onSuccess { result.success(true) }
            .onFailure { result.error("unavailable", "No application can open the Telegram link", null) }
    }

    private fun openExternalUrl(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("url")?.let(Uri::parse)
        if (uri == null) {
            result.error("invalid_url", "Only official niraNG release links are allowed", null)
            return
        }
        val allowed = uri.scheme.equals("https", true) &&
            uri.host.equals("github.com", true) &&
            uri.path?.startsWith("/bardia-us/niraNG/releases/") == true
        if (!allowed) {
            result.error("invalid_url", "Only official niraNG release links are allowed", null)
            return
        }
        runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            .onSuccess { result.success(true) }
            .onFailure { result.error("unavailable", "No application can open the release link", null) }
    }

    private fun bootstrap(): Map<String, Any?> {
        val snapshot = repository.snapshot()
        return mapOf(
            "servers" to repository.safeServers(),
            "usage" to snapshot.usage.toMap(),
            "lastUpdated" to snapshot.lastUpdatedEpochMillis,
            "connection" to ConnectionStore.snapshot(),
            "settings" to NativeSettings(activity).toMap(),
            "coreVersion" to activity.getSharedPreferences("nirang_installation", Activity.MODE_PRIVATE)
                .getString("coreVersion", "Bundled"),
            "appVersion" to BuildConfig.VERSION_NAME,
            "subscriptionConfigured" to BuildConfig.SUBSCRIPTION_URL.isNotBlank(),
            "telegramEligible" to NativeSettings(activity).telegramReminderEligible(),
            "deletedServerCount" to repository.deletedCount(),
        )
    }

    private fun success(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            runCatching(block)
                .onSuccess { value -> postToFlutter { result.success(value) } }
                .onFailure { error -> postToFlutter { result.error("native", safeError(error), null) } }
        }
    }

    private fun postToFlutter(block: () -> Unit) {
        mainHandler.post {
            if (!disposed.get()) runCatching(block)
        }
    }

    private fun safeError(error: Throwable): String = (error.message ?: error.javaClass.simpleName)
        .replace(Regex("https?://\\S+", RegexOption.IGNORE_CASE), "endpoint")
        .replace(Regex("(?i)(vless|vmess|trojan)://\\S+"), "configuration")
        .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "identifier")
        .take(240)

    companion object {
        private const val METHOD_CHANNEL = "dev.nirang.client/control"
        private const val EVENT_CHANNEL = "dev.nirang.client/events"
        private val ACTIVE_CONNECTION_STATES = setOf(
            ConnectionState.PREPARING,
            ConnectionState.CONNECTING,
            ConnectionState.CONNECTED,
            ConnectionState.RESTARTING,
            ConnectionState.SWITCHING,
            ConnectionState.RECONNECTING,
        )
        private val RESTART_ELIGIBLE_STATES = ACTIVE_CONNECTION_STATES
    }
}
