package dev.nirang.client.bridge

import android.app.Activity
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Intent
import android.graphics.drawable.Icon
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import dev.nirang.client.BuildConfig
import dev.nirang.client.MainActivity
import dev.nirang.client.R
import dev.nirang.client.logs.SafeLog
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.model.ServerEligibility
import dev.nirang.client.ping.PingManager
import dev.nirang.client.registration.DeviceRegistrationManager
import dev.nirang.client.registration.RemoteAccessState
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.subscription.SubscriptionScheduler
import dev.nirang.client.update.UpdateDownloadEvents
import dev.nirang.client.update.UpdateInstaller
import dev.nirang.client.traffic.MeasuredTrafficRepository
import dev.nirang.client.vpn.ConnectionStore
import dev.nirang.client.vpn.NirangVpnService
import dev.nirang.client.vpn.NirangTileService
import dev.nirang.client.vpn.RestartPolicy
import dev.nirang.client.vpn.ServerSelection
import dev.nirang.client.vpn.ConnectionPreflight
import dev.nirang.client.vpn.AetherPreparationCoordinator
import dev.nirang.client.vpn.AetherProfileSave
import dev.nirang.client.vpn.AsyncNativeStop
import dev.nirang.client.xray.XrayCore
import dev.nirang.client.cores.aether.AetherSession
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.io.ByteArrayOutputStream
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

class NirangBridge(
    private val activity: Activity,
    flutterEngine: FlutterEngine,
    private val requestVpnPermission: (String, MethodChannel.Result) -> Unit,
) : MethodChannel.MethodCallHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    // A startup API timeout must not queue local settings/server operations
    // behind an unavailable network.
    private val accessExecutor = Executors.newSingleThreadExecutor()
    private val aetherExecutor = Executors.newSingleThreadExecutor()
    private val feedbackExecutor = Executors.newSingleThreadExecutor()
    private val feedbackSending = AtomicBoolean(false)
    private val diagnosticsExecutor = Executors.newSingleThreadExecutor()
    private val diagnostics = java.util.concurrent.atomic.AtomicReference<dev.nirang.client.ping.ProbeCancellation?>()
    private val aetherPreparing = AtomicBoolean(false)
    private val aetherPreparations = AetherPreparationCoordinator.shared
    private val disposed = AtomicBoolean(false)
    private val repository = SubscriptionRepository(activity.applicationContext)
    private val pingManager = PingManager(activity.applicationContext, repository)
    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
    private val updateEventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_EVENT_CHANNEL)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(NativeEvents)
        updateEventChannel.setStreamHandler(UpdateDownloadEvents)
        UpdateInstaller.initialize(activity.applicationContext)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "uiCaptureContext" -> {
                fun text(value:String):String {
                    val cleaned=value.replace(Regex("[\\u0000-\\u001f\\u007f]")," ").trim()
                    val points=cleaned.codePoints().limit(20).toArray();return String(points,0,points.size)
                }
                val power=activity.getSystemService(PowerManager::class.java)
                result.success(mapOf(
                    "manufacturer" to text(Build.MANUFACTURER),
                    "model" to text(Build.MODEL),
                    "android_sdk" to Build.VERSION.SDK_INT,
                    "soc_model" to if(Build.VERSION.SDK_INT>=31) text(Build.SOC_MODEL) else null,
                    "power_save" to runCatching { power?.isPowerSaveMode }.getOrNull(),
                    "thermal_status" to if(Build.VERSION.SDK_INT>=29) runCatching { power?.currentThermalStatus }.getOrNull() else null,
                ))
            }
            "feedbackContext" -> success(result) {
                val server=repository.selectedServer()
                // Limit report metadata only; preserve the selected source/config exactly.
                val reportName=server?.name?.replace(Regex("[\\u0000-\\u001f\\u007f]")," ")?.trim()?.let { value ->
                    val points=value.codePoints().limit(120).toArray()
                    String(points,0,points.size).ifBlank { "Selected profile" }
                }
                val config=server?.let { it.customProfile?.payload ?: it.toPrivateJson().toString(2) }
                buildMap<String,Any?> {
                    if(server!=null) put("selected_server",mapOf("id" to server.id,"name" to reportName,"protocol" to server.protocol,"core" to (server.customProfile?.engine ?: "xray")))
                    if(call.argument<Boolean>("includeConfig")==true && config!=null) {
                        require(config.toByteArray(Charsets.UTF_8).size<=65536) { "Selected configuration is too large" }
                        put("selected_config",config)
                    }
                }
            }
            "submitFeedback" -> {
                val values=call.arguments as? Map<*,*> ?: run { result.error("feedback_failed","Invalid report",null);return }
                if(!feedbackSending.compareAndSet(false,true)) { result.error("feedback_busy","Feedback is already sending",null);return }
                feedbackExecutor.execute {
                    try {
                        val response=DeviceRegistrationManager.submitFeedback(activity.applicationContext,org.json.JSONObject(values))
                        postToFlutter { result.success(response) }
                    } catch(e:Exception) {
                        val code=e.message?.takeIf { it in setOf("feedback_unavailable","feedback_rate_limited","feedback_conflict","feedback_unauthorized","feedback_too_large","feedback_failed") } ?: "feedback_failed"
                        postToFlutter { result.error(code,"Feedback could not be delivered",null) }
                    } finally { feedbackSending.set(false) }
                }
            }
            "shareProblemReport" -> {
                val text=call.argument<String>("text")
                if(text==null || text.length>98304) { result.error("report","Invalid report",null);return }
                try {
                    activity.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
                        type="text/plain"
                        putExtra(Intent.EXTRA_TEXT,text)
                    },null))
                    result.success(null)
                } catch(_:Exception) { result.error("report","Sharing is unavailable; copy the report instead",null) }
            }
            "getAetherEndpointSuggestion" -> success(result) {
                val values=requireNotNull(call.argument<Map<String,Any?>>("values"))
                dev.nirang.client.cores.aether.AetherEndpointMemory.suggestion(activity,org.json.JSONObject(values).toString())
            }
            "cancelConnectionDiagnosis" -> {
                diagnostics.get()?.cancel()
                result.success(null)
            }
            "diagnoseConnection" -> {
                val cancellation=dev.nirang.client.ping.ProbeCancellation(AsyncNativeStop::execute)
                if(!diagnostics.compareAndSet(null,cancellation)) { result.error("busy","A diagnostic is already running",null);return }
                diagnosticsExecutor.execute {
                    try {
                        val requestId=call.argument<String>("requestId")?.takeIf { it.matches(Regex("[a-zA-Z0-9_-]{1,64}")) }
                        val report=dev.nirang.client.vpn.ConnectionDiagnostics.run(activity.applicationContext,cancellation) { row ->
                            if(requestId!=null) NativeEvents.emit("connectionDiagnostic",mapOf("requestId" to requestId,"row" to row))
                        }
                        postToFlutter { result.success(report) }
                    } catch(e:Exception) { postToFlutter { result.error("diagnostic",safeError(e),null) } }
                    finally { diagnostics.compareAndSet(cancellation,null) }
                }
            }
            "deviceRegistrationStatus" -> {
                deviceRegistrationStatus(result)
            }
            "verifyDeviceAccess" -> verifyDeviceAccess(result)
            "acceptDeviceRegistration" -> acceptDeviceRegistration(result)
            "exitApplication" -> {
                activity.finishAndRemoveTask()
                result.success(true)
            }
            "initialize" -> initialize(result)
            "getBootstrap" -> success(result) { bootstrap() }
            "getMeasuredTraffic" -> success(result) { MeasuredTrafficRepository.get(activity).snapshot() }
            "refreshSubscription" -> refreshSubscription(result)
            "selectServer" -> selectServer(call, result)
            "reorderServers" -> reorderServers(call, result)
            "getAetherProfile" -> success(result) {
                val id=requireNotNull(call.argument<String>("id"))
                val state=ConnectionStore.snapshot()
                repository.aetherProfile(id) + if(state["serverId"] == id && state["aetherEndpoint"] != null)
                    mapOf("activePath" to mapOf("endpoint" to state["aetherEndpoint"],"innerEndpoint" to state["aetherInnerEndpoint"])) else emptyMap()
            }
            "saveAetherProfile" -> success(result) {
                val id=call.argument<String>("id")
                val values=requireNotNull(call.argument<Map<String,Any?>>("values"))
                val rows=AetherProfileSave.save(id,
                    readPayload={ repository.server(it)?.customProfile?.payload },
                    persist={ repository.saveAetherProfile(id,requireNotNull(call.argument<String>("name")),values) },
                    activeServerId=NirangVpnService::activeServerId,
                    isActive={ ConnectionStore.state() in RESTART_ELIGIBLE_STATES },
                    restart={ NirangVpnService.restart(activity,it) },
                )
                NativeEvents.emit("servers",rows)
                rows
            }
            "scanAetherDraft" -> scanAetherDraft(call,result)
            "prepareAetherProfile" -> prepareAetherProfile(call,result)
            "renewAetherIdentity" -> prepareAetherProfile(call,result,renew = true)
            "cancelAetherPreparation" -> {
                aetherPreparations.cancel(AsyncNativeStop::execute)
                result.success(true)
            }
            "updateServerProfile" -> success(result) {
                val id = requireNotNull(call.argument<String>("id"))
                val values = requireNotNull(call.argument<Map<String, Any?>>("values"))
                require(repository.updateServerProfile(id, values)) { "Server not found" }
                repository.safeServers()
            }
            "deleteServer" -> deleteServer(call, result)
            "restoreDeletedServers" -> restoreDeletedServers(result)
            "connect" -> connect(call, result)
            "disconnect" -> {
                aetherPreparations.cancel(AsyncNativeStop::execute)
                NirangVpnService.stop(activity)
                result.success(true)
            }
            "restartService" -> restartService(result)
            "refreshPublicIp" -> result.success(NirangVpnService.refreshPublicIp(activity))
            "requestQuickSettingsTile" -> requestQuickSettingsTile(result)
            "batteryOptimizationStatus" -> {
                val powerManager = activity.getSystemService(PowerManager::class.java)
                result.success(powerManager?.isIgnoringBatteryOptimizations(activity.packageName) == true)
            }
            "openBatteryOptimizationSettings" -> {
                runCatching {
                    activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                }.onSuccess { result.success(true) }
                    .onFailure { result.error("unavailable", "Battery optimization settings are unavailable", null) }
            }
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
            "tcpPingAll" -> {
                pingManager.testAllTcp()
                result.success(true)
            }
            "cancelPing" -> {
                pingManager.cancel()
                result.success(true)
            }
            "updateSettings" -> updateSettings(call, result)
            "resetSettings" -> resetSettings(result)
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
            "claimWhatsNew" -> success(result) {
                synchronized(whatsNewLock) {
                    val installation = activity.getSharedPreferences("nirang_installation", Activity.MODE_PRIVATE)
                    val build = BuildConfig.BASE_VERSION_CODE
                    if (installation.getInt("whatsNewSeenBuild", 0) >= build) {
                        false
                    } else {
                        installation.edit()
                            .putInt("whatsNewSeenBuild", build)
                            .putInt("whatsNewUpgradeFromBuild", 0)
                            .commit()
                    }
                }
            }
            "recordFlutterError" -> {
                val message = call.argument<String>("message").orEmpty()
                SafeLog.error(activity, "Flutter error: ${message.take(1_200)}")
                result.success(true)
            }
            "openTelegram" -> openTelegram(result)
            "openExternalUrl" -> openExternalUrl(call, result)
            "supportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "getInstalledApps" -> installedApps(result)
            "startUpdateDownload" -> startUpdateDownload(call, result)
            "resumeUpdateDownload" -> {
                runCatching { UpdateInstaller.resume(activity) }
                    .onSuccess(result::success)
                    .onFailure { result.error("update_download_failed", safeError(it), null) }
            }
            "getUpdateDownload" -> result.success(UpdateInstaller.snapshot(activity))
            "cancelUpdateDownload" -> result.success(UpdateInstaller.cancel(activity))
            "deleteUpdateDownload" -> result.success(UpdateInstaller.delete(activity))
            "installDownloadedUpdate" -> {
                runCatching { UpdateInstaller.launchInstaller(activity) }
                    .onSuccess { result.success(true) }
                    .onFailure { result.error("installer_unavailable", safeError(it), null) }
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        updateEventChannel.setStreamHandler(null)
        pingManager.close()
        executor.shutdownNow()
        accessExecutor.shutdownNow()
        aetherPreparations.cancel(AsyncNativeStop::execute)
        aetherExecutor.shutdownNow()
        diagnostics.getAndSet(null)?.cancel()
        feedbackExecutor.shutdownNow()
        diagnosticsExecutor.shutdownNow()
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
                handleRemoteAccessFailure(error)
                postToFlutter { result.error(remoteErrorCode(error, "startup"), publicErrorMessage(error), remoteErrorDetails(error)) }
            }
        }
    }

    private fun deviceRegistrationStatus(result: MethodChannel.Result) {
        // Display saved policy immediately. Flutter refreshes it after the
        // local screen paints; Retry explicitly checks remote policy too.
        val localState = if (DeviceRegistrationManager.hasConsent(activity))
            DeviceRegistrationManager.localAccessState(activity) else null
        if (localState != null) {
            result.error(if (localState == RemoteAccessState.BLOCKED) "blocked" else "outdated", "Device access policy requires attention", null)
        } else {
            result.success(DeviceRegistrationManager.hasConsent(activity))
        }
    }

    private fun verifyDeviceAccess(result: MethodChannel.Result) {
        if (!DeviceRegistrationManager.hasConsent(activity)) {
            result.error("consent_required", "Device registration consent is required", null)
            return
        }
        accessExecutor.execute {
            runCatching { DeviceRegistrationManager.requireAllowed(activity, timeoutMillis = 7_000) }
                .onSuccess {
                    postToFlutter {
                        result.success(true)
                        (activity as? MainActivity)?.continuePendingTileConnection()
                    }
                }
                .onFailure { error ->
                    handleRemoteAccessFailure(error)
                    postToFlutter {
                        result.error(remoteErrorCode(error, "registration"), publicErrorMessage(error), remoteErrorDetails(error))
                    }
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
            }.onSuccess { accepted ->
                postToFlutter {
                    result.success(accepted)
                }
            }
                .onFailure { error ->
                    handleRemoteAccessFailure(error)
                    postToFlutter {
                        result.error(remoteErrorCode(error, "registration"), publicErrorMessage(error), remoteErrorDetails(error))
                    }
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
                NativeEvents.emit("accessAllowed", null)
                postToFlutter { result.success(data) }
                postToFlutter { (activity as? MainActivity)?.continuePendingTileConnection() }
            } catch (error: Exception) {
                SafeLog.warning(activity, "Subscription update failed")
                handleRemoteAccessFailure(error)
                postToFlutter {
                    result.error(remoteErrorCode(error, "subscription"), publicErrorMessage(error), remoteErrorDetails(error))
                }
            }
        }
    }

    private fun selectServer(call: MethodCall, result: MethodChannel.Result) {
        success(result) {
        val id = call.argument<String>("id")
        val server = id?.let(repository::server)
        if (id == null || server == null) {
            throw IllegalArgumentException("Server not found")
        }
        val connection = ConnectionStore.snapshot()
        val activeId = connection["serverId"] as? String
        val state = ConnectionStore.state()
        val requiresSwitch = activeId != null && activeId != id && state in ACTIVE_CONNECTION_STATES
        ServerSelection.select(
            id, requiresSwitch,
            persist = { repository.select(it) },
            queueSwitch = { NirangVpnService.switchServer(activity, it) },
            validateCandidate = { ConnectionPreflight.validate(activity,server) },
        )
        SafeLog.info(activity, if (requiresSwitch) "Server switch queued" else "Server selected")
        // Return the requested choice immediately. ConnectionStore still owns
        // the actual restart/connected/error status and restart rollback.
        repository.safeServers()
        }
    }

    private fun installedApps(result: MethodChannel.Result) {
        executor.execute {
            val apps = runCatching {
                val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
                activity.packageManager.queryIntentActivities(launcher, 0)
                    .asSequence()
                    .mapNotNull { info ->
                        val packageName = info.activityInfo?.packageName?.takeIf { it != activity.packageName }
                            ?: return@mapNotNull null
                        val icon = runCatching {
                            val drawable = info.loadIcon(activity.packageManager)
                            val bitmap = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888)
                            drawable.setBounds(0, 0, 64, 64)
                            drawable.draw(Canvas(bitmap))
                            ByteArrayOutputStream().use { output ->
                                bitmap.compress(Bitmap.CompressFormat.PNG, 90, output)
                                bitmap.recycle()
                                output.toByteArray()
                            }
                        }.getOrNull()
                        mapOf(
                            "packageName" to packageName,
                            "name" to info.loadLabel(activity.packageManager).toString().take(120),
                            "icon" to icon,
                        )
                    }
                    .distinctBy { it["packageName"] }
                    .sortedBy { (it["name"] as String).lowercase() }
                    .toList()
            }.getOrElse { emptyList() }
            postToFlutter { result.success(apps) }
        }
    }

    private fun reorderServers(call: MethodCall, result: MethodChannel.Result) {
        val ids = call.argument<List<String>>("ids").orEmpty()
        if (!repository.reorder(ids)) {
            result.error("invalid_order", "Server order no longer matches the current subscription", null)
            return
        }
        val servers = repository.safeServers()
        NativeEvents.emit("servers", servers)
        result.success(servers)
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
        aetherPreparations.cancel(AsyncNativeStop::execute)
        if (!DeviceRegistrationManager.hasConsent(activity)) {
            result.error("consent_required", "Device registration consent is required", null)
            return
        }
        val requested = call.argument<String>("id") ?: repository.selectedServer()?.id
        if (DeviceRegistrationManager.isLocallyBlocked(activity)) {
            result.error("blocked", "This device has been blocked by the administrator", null)
            return
        }
        continueConnect(requested, result)
    }

    private fun scanAetherDraft(call:MethodCall,result:MethodChannel.Result) {
        if(!aetherPreparing.compareAndSet(false,true)) { result.error("busy","Aether preparation is already running",null);return }
        val generation=try { aetherPreparations.begin() } catch(e:Exception) { aetherPreparing.set(false);result.error("busy","Aether operation in progress",null);return }
        aetherExecutor.execute {
            var directory:java.io.File?=null
            try {
                check(DeviceRegistrationManager.hasConsent(activity) && !DeviceRegistrationManager.isLocallyBlocked(activity)) { "Device access is required" }
                val values=requireNotNull(call.argument<Map<String,Any?>>("values"))
                val config=org.json.JSONObject(values).apply { put("startupTimeoutSeconds",90) }.toString()
                val options=dev.nirang.client.cores.aether.AetherOptions.parse(config)
                check(options.psiphon != "only") { "Psiphon-only has no WARP endpoint" }
                directory=java.nio.file.Files.createTempDirectory(activity.noBackupFilesDir.toPath(),"aether-draft-").toFile()
                android.system.Os.chmod(directory.absolutePath,448)
                dev.nirang.client.ping.PrivateProbePorts.reserve(2).use { ports ->
                    val session=AetherSession(activity.applicationContext,socksPort=ports.ports[0],psiphonPort=ports.ports[1],
                        storageDirectory=directory,onProgress={ stage ->
                            check(aetherPreparations.current(generation) && !disposed.get()) { "Aether scan cancelled" }
                            NativeEvents.emit("aetherPreparation",mapOf("state" to stage))
                        })
                    check(aetherPreparations.install(generation,session::stop)) { "Aether scan cancelled" }
                    ports.releaseForStart()
                    try {
                        session.scan(config)
                        check(aetherPreparations.current(generation) && !disposed.get()) { "Aether scan cancelled" }
                        val path=session.selectedPath ?: error("The core did not report an endpoint")
                        postToFlutter {
                            if (aetherPreparations.validResult(generation) && !disposed.get()) result.success(mapOf("state" to "ready","scan" to path))
                            else result.error("cancelled","Aether scan cancelled",null)
                        }
                    } finally { session.stop() }
                }
            } catch(e:Throwable) { postToFlutter { result.error("aether",safeError(e),null) } }
            finally { aetherPreparations.finish(generation);directory?.deleteRecursively();aetherPreparing.set(false) }
        }
    }

    private fun prepareAetherProfile(call:MethodCall,result:MethodChannel.Result,renew:Boolean = false) {
        if(!aetherPreparing.compareAndSet(false,true)) { result.error("busy","Aether preparation is already running",null);return }
        val generation = try { aetherPreparations.begin() } catch (_: IllegalStateException) {
            aetherPreparing.set(false)
            result.error("busy", "Aether preparation is already running", null)
            return
        }
        aetherExecutor.execute {
            try {
                check(DeviceRegistrationManager.hasConsent(activity) && !DeviceRegistrationManager.isLocallyBlocked(activity)) { "Device access is required" }
                val id=requireNotNull(call.argument<String>("id"))
                val record=repository.server(id) ?: error("Aether profile not found")
                val profile=record.customProfile?.takeIf { it.kind == "aether" } ?: error("Not an Aether profile")
                val active=ConnectionStore.current()
                val activeAether=(NirangVpnService.activeServerId() ?: active.serverId)?.let(repository::server)?.customProfile?.kind == "aether"
                check(!activeAether || active.state !in ACTIVE_CONNECTION_STATES + ConnectionState.STOPPING) { "Disconnect Aether before preparing another profile" }
                check(aetherPreparations.current(generation) && !disposed.get()) { "Aether preparation cancelled" }
                val session=AetherSession(activity.applicationContext,onProgress={ stage ->
                    check(aetherPreparations.current(generation) && !disposed.get()) { "Aether preparation cancelled" }
                    NativeEvents.emit("aetherPreparation",mapOf("id" to id,"state" to stage))
                })
                check(aetherPreparations.install(generation, session::stop)) { "Aether preparation cancelled" }
                check(aetherPreparations.current(generation) && !disposed.get()) { "Aether preparation cancelled" }
                val rescan=call.argument<Boolean>("rescan") == true
                if(rescan) session.scan(profile.payload)
                else session.prepare(profile.payload,if(active.state == ConnectionState.CONNECTED && XrayCore.isRunning()) 10809 else 0, forceRenew = renew)
                check(aetherPreparations.current(generation) && !disposed.get()) { "Aether preparation cancelled" }
                val response=mapOf("state" to if(rescan) "ready" else "prepared")
                postToFlutter { result.success(response) }
            } catch(error:Throwable) {
                postToFlutter { result.error("aether",safeError(error),null) }
            } finally {
                aetherPreparations.finish(generation)
                aetherPreparing.set(false)
            }
        }
    }

    /** Uses the exact normal connect/access/permission path after a Tile-opened Activity is ready. */
    fun connectFromTileIfReady(): Boolean {
        if (!DeviceRegistrationManager.hasConsent(activity)) return false
        val server = repository.selectedServer() ?: return false
        connect(
            MethodCall("connect", mapOf("id" to server.id)),
            object : MethodChannel.Result {
                override fun success(result: Any?) = Unit
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit
                override fun notImplemented() = Unit
            },
        )
        return true
    }

    private fun continueConnect(requested: String?, result: MethodChannel.Result) {
        if (ConnectionStore.state() in ACTIVE_CONNECTION_STATES + ConnectionState.STOPPING) {
            result.error("busy", "A VPN transition is already in progress", null)
            return
        }
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

    private fun handleRemoteAccessFailure(error: Throwable) {
        val denied = error as? dev.nirang.client.registration.RemoteAccessException ?: return
        if (denied.accessState == RemoteAccessState.UNKNOWN) return
        NirangVpnService.stop(activity)
        NativeEvents.emit(
            if (denied.accessState == RemoteAccessState.BLOCKED) "accessBlocked" else "updateRequired",
            mapOf(
                "reason" to denied.apiReason,
                "minimumVersion" to denied.minimumVersion,
                "minimumBuild" to denied.minimumBuild,
            ),
        )
    }

    private fun remoteErrorCode(error: Throwable, fallback: String): String {
        val denied = error as? dev.nirang.client.registration.RemoteAccessException
        return when (denied?.accessState) {
            RemoteAccessState.BLOCKED -> "blocked"
            RemoteAccessState.OUTDATED -> "outdated"
            else -> classifyNetworkError(error, fallback)
        }
    }

    private fun classifyNetworkError(error: Throwable, fallback: String): String = when (error) {
        is SocketTimeoutException -> "timeout"
        is UnknownHostException, is NoRouteToHostException, is ConnectException -> "host_unreachable"
        is java.io.IOException -> if (fallback == "subscription") "subscription_network" else "network"
        else -> fallback
    }

    private fun publicErrorMessage(error: Throwable): String = when (remoteErrorCode(error, "network")) {
        "blocked" -> "Access is blocked"
        "outdated" -> "An app update is required"
        "timeout" -> "The request timed out"
        "host_unreachable" -> "The service is unreachable"
        "subscription_network" -> "The subscription could not be downloaded"
        else -> "The request could not be completed"
    }

    private fun remoteErrorDetails(error: Throwable): Map<String, Any?>? {
        val denied = error as? dev.nirang.client.registration.RemoteAccessException ?: return null
        return mapOf(
            "reason" to denied.apiReason,
            "minimumVersion" to denied.minimumVersion,
            "minimumBuild" to denied.minimumBuild,
        )
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
            (uri.path == "/bardia-us/niraNG" || uri.path == "/bardia-us/niraNG/" || uri.path?.startsWith("/bardia-us/niraNG/releases/") == true)
        if (!allowed) {
            result.error("invalid_url", "Only official niraNG release links are allowed", null)
            return
        }
        runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
            .onSuccess { result.success(true) }
            .onFailure { result.error("unavailable", "No application can open the release link", null) }
    }

    private fun resetSettings(result: MethodChannel.Result) {
        executor.execute {
            runCatching {
                val settings = NativeSettings(activity).resetAll()
                SubscriptionScheduler.reconcile(activity)
                val activeId = ConnectionStore.snapshot()["serverId"] as? String
                if (activeId != null && ConnectionStore.state() in RESTART_ELIGIBLE_STATES) {
                    NirangVpnService.restart(activity, activeId)
                }
                NativeEvents.emit("settings", settings)
                settings
            }.onSuccess { settings -> postToFlutter { result.success(settings) } }
                .onFailure { error -> postToFlutter { result.error("reset_failed", safeError(error), null) } }
        }
    }

    private fun startUpdateDownload(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url").orEmpty()
        val expectedSize = call.argument<Number>("size")?.toLong() ?: 0L
        val sha256 = call.argument<String>("sha256")?.takeIf(String::isNotBlank)
        val name = call.argument<String>("name").orEmpty()
        val version = call.argument<String>("version").orEmpty()
        runCatching { UpdateInstaller.start(activity, url, expectedSize, sha256, name, version) }
            .onSuccess(result::success)
            .onFailure { result.error("update_download_failed", safeError(it), null) }
    }

    private fun bootstrap(): Map<String, Any?> {
        val snapshot = repository.snapshot()
        val installation = activity.getSharedPreferences("nirang_installation", Activity.MODE_PRIVATE)
        val appBuild = BuildConfig.BASE_VERSION_CODE
        var lastLaunchedBuild = installation.getInt("lastLaunchedBuild", 0)
        var upgradeFromBuild = installation.getInt("whatsNewUpgradeFromBuild", 0)
        if (lastLaunchedBuild <= 0) {
            // Fresh installs establish a baseline and show bundled notes once;
            // later launches use the persisted seen-build ledger.
            lastLaunchedBuild = appBuild
            upgradeFromBuild = 0
            installation.edit()
                .putInt("lastLaunchedBuild", appBuild)
                .putInt("whatsNewUpgradeFromBuild", 0)
                .apply()
        } else if (appBuild > lastLaunchedBuild) {
            upgradeFromBuild = lastLaunchedBuild
            installation.edit()
                .putInt("lastLaunchedBuild", appBuild)
                .putInt("whatsNewUpgradeFromBuild", upgradeFromBuild)
                .apply()
        }
        return mapOf(
            "servers" to repository.safeServers(),
            "usage" to snapshot.usage.toMap(),
            "lastUpdated" to snapshot.lastUpdatedEpochMillis,
            "connection" to ConnectionStore.snapshot(),
            "settings" to NativeSettings(activity).toMap(),
            "coreVersion" to installation.getString("coreVersion", "Bundled"),
            "appVersion" to BuildConfig.VERSION_NAME,
            "appBuild" to appBuild,
            "whatsNewSeenBuild" to installation.getInt("whatsNewSeenBuild", 0),
            "whatsNewUpgradeFromBuild" to upgradeFromBuild,
            "subscriptionConfigured" to true,
            "telegramEligible" to NativeSettings(activity).telegramReminderEligible(),
            "telegramStage" to NativeSettings(activity).telegramReminderStage(),
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
        .replace(Regex("(?i)(vless|vmess|trojan|ss|socks5?|https?|hy2|hysteria2?)://\\S+"), "configuration")
        .replace(Regex("[0-9a-fA-F]{8}-[0-9a-fA-F-]{27,}"), "identifier")
        .take(240)

    companion object {
        private val whatsNewLock = Any()
        private const val METHOD_CHANNEL = "dev.nirang.client/control"
        private const val EVENT_CHANNEL = "dev.nirang.client/events"
        private const val UPDATE_EVENT_CHANNEL = "dev.nirang.client/update_download"
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
