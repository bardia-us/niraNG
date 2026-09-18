package dev.nirang.client.update

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.FileProvider
import dev.nirang.client.BuildConfig
import dev.nirang.client.logs.SafeLog
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import javax.net.ssl.HttpsURLConnection

/** Process-scoped manager: downloads survive dialog/navigation changes and are resumable. */
object UpdateInstaller {
    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 30_000
    private const val MAX_APK_BYTES = 250L * 1024 * 1024
    private const val MAX_REDIRECTS = 5
    private const val BUFFER_BYTES = 256 * 1024
    private const val PROGRESS_BYTES = 1024 * 1024
    private const val PROGRESS_INTERVAL_MS = 400L
    private const val PREFS = "nirang_update_download"
    private val executor = Executors.newSingleThreadExecutor()
    private val downloading = AtomicBoolean(false)
    private val generation = AtomicLong(0)
    private val activeReceived = AtomicLong(0)
    @Volatile private var activeConnection: HttpsURLConnection? = null

    fun initialize(context: Context) {
        val wanted = prefs(context).getString("version", "").orEmpty()
        if (wanted.isNotBlank() && compareVersions(BuildConfig.VERSION_NAME, wanted) >= 0) delete(context)
        else publish(snapshot(context))
    }

    fun snapshot(context: Context): Map<String, Any?> {
        val p = prefs(context)
        val partial = partFile(context)
        val complete = apkFile(context)
        val total = p.getLong("total", 0L)
        val persistedReceived = when { complete.isFile -> complete.length(); partial.isFile -> partial.length(); else -> 0L }
        var state = p.getString("state", "idle").orEmpty()
        val received = if (state == "downloading" && downloading.get()) {
            maxOf(persistedReceived, activeReceived.get())
        } else {
            persistedReceived
        }
        if (state in setOf("downloading", "verifying") && !downloading.get()) {
            state = if (state == "downloading" && received in 1 until total) "paused" else "failed"
        }
        if (state == "complete" && (!complete.isFile || received != total)) state = "failed"
        return mapOf(
            "state" to state, "received" to received, "total" to total,
            "name" to p.getString("name", "").orEmpty(),
            "version" to p.getString("version", "").orEmpty(),
            "url" to p.getString("url", "").orEmpty(),
            "canResume" to (partial.isFile && received in 1 until total),
            "canInstall" to (complete.isFile && received == total && total > 0),
        )
    }

    fun start(context: Context, url: String, size: Long, sha256: String?, name: String, version: String): Map<String, Any?> {
        validateRequest(url, size, sha256, name)
        val p = prefs(context)
        val same = p.getString("url", "") == url && p.getLong("total", 0L) == size &&
            p.getString("sha256", "").orEmpty().equals(sha256.orEmpty(), true)
        val existing = snapshot(context)
        if (same && existing["canInstall"] == true) return existing.also(::publish)
        if (!same) {
            generation.incrementAndGet()
            activeConnection?.disconnect()
            clearFiles(context)
            activeReceived.set(0)
            p.edit().clear().commit()
        }
        p.edit().putString("url", url).putLong("total", size).putString("sha256", sha256.orEmpty())
            .putString("name", name).putString("version", version).putString("state", "downloading").apply()
        if (!downloading.get() || !same) {
            val token = generation.incrementAndGet()
            downloading.set(true)
            activeReceived.set(partFile(context).takeIf(File::isFile)?.length() ?: 0L)
            executor.execute { download(context.applicationContext, token) }
        }
        return snapshot(context).toMutableMap().apply { put("state", "downloading") }.also(::publish)
    }

    fun cancel(context: Context): Map<String, Any?> {
        generation.incrementAndGet()
        activeConnection?.disconnect()
        downloading.set(false)
        activeReceived.set(partFile(context).takeIf(File::isFile)?.length() ?: 0L)
        prefs(context).edit().putString("state", "paused").apply()
        return snapshot(context).also(::publish)
    }

    fun resume(context: Context): Map<String, Any?> {
        val p = prefs(context)
        return start(
            context,
            p.getString("url", "").orEmpty(),
            p.getLong("total", 0L),
            p.getString("sha256", "").orEmpty().ifBlank { null },
            p.getString("name", "").orEmpty(),
            p.getString("version", "").orEmpty(),
        )
    }

    fun delete(context: Context): Map<String, Any?> {
        generation.incrementAndGet()
        activeConnection?.disconnect()
        downloading.set(false)
        activeReceived.set(0)
        clearFiles(context)
        prefs(context).edit().clear().commit()
        return snapshot(context).also(::publish)
    }

    fun launchInstaller(activity: Activity) {
        val apk = apkFile(activity)
        require(apk.isFile && apk.length() > 0) { "Downloaded APK is unavailable" }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
    }

    private fun download(context: Context, token: Long) {
        val p = prefs(context)
        val startedAt = SystemClock.elapsedRealtime()
        try {
            val url = p.getString("url", "").orEmpty()
            val expected = p.getLong("total", 0L)
            val expectedDigest = p.getString("sha256", "").orEmpty().ifBlank { null }
            val partial = partFile(context)
            apkFile(context).delete()
            var offset = partial.takeIf(File::isFile)?.length() ?: 0L
            if (offset !in 0 until expected) { partial.delete(); offset = 0 }
            activeReceived.set(offset)
            var current = URI(url).also(::requireOfficialInitialUrl).toURL()
            var redirects = 0
            while (true) {
                ensureActive(token)
                val connection = open(current, offset)
                activeConnection = connection
                try {
                    val status = connection.responseCode
                    if (status in 300..399) {
                        if (redirects++ >= MAX_REDIRECTS) throw IOException("Too many update redirects")
                        current = URL(current, connection.getHeaderField("Location") ?: throw IOException("Missing redirect"))
                            .also(::requireAllowedDownloadHost)
                        continue
                    }
                    if (status != HttpURLConnection.HTTP_OK && status != HttpURLConnection.HTTP_PARTIAL) {
                        throw IOException("Update download failed with HTTP $status")
                    }
                    val append = offset > 0 && status == HttpURLConnection.HTTP_PARTIAL &&
                        connection.getHeaderField("Content-Range")?.startsWith("bytes $offset-") == true
                    if (!append) { offset = 0; partial.delete() }
                    activeReceived.set(offset)
                    val declared = connection.contentLengthLong
                    if (declared > MAX_APK_BYTES || (declared > 0 && offset + declared > MAX_APK_BYTES)) throw IOException("Update is too large")
                    copyResponse(connection, partial, expected, offset, append, token)
                    break
                } finally {
                    connection.disconnect()
                    if (activeConnection === connection) activeConnection = null
                }
            }
            ensureActive(token)
            if (partial.length() != expected) throw IOException("Downloaded update size does not match GitHub")
            val downloadedAt = SystemClock.elapsedRealtime()
            p.edit().putString("state", "verifying").apply()
            publish(snapshot(context))
            verifyDigest(partial, expectedDigest, token)
            val digestVerifiedAt = SystemClock.elapsedRealtime()
            verifySigningCertificate(context, partial)
            val signatureVerifiedAt = SystemClock.elapsedRealtime()
            if (!partial.renameTo(apkFile(context))) throw IOException("Downloaded update could not be finalized")
            activeReceived.set(expected)
            p.edit().putString("state", "complete").apply()
            SafeLog.info(
                context,
                "Update stages: download=${downloadedAt - startedAt}ms, sha256=${digestVerifiedAt - downloadedAt}ms, signature=${signatureVerifiedAt - digestVerifiedAt}ms",
            )
            publish(snapshot(context))
        } catch (_: DownloadCancelledException) {
            if (generation.get() == token) {
                p.edit().putString("state", "paused").apply(); publish(snapshot(context))
            }
        } catch (_: Throwable) {
            if (generation.get() == token) {
                if (partFile(context).length() >= p.getLong("total", 0L)) partFile(context).delete()
                p.edit().putString("state", "failed").apply(); publish(snapshot(context))
            }
        } finally { if (generation.get() == token) downloading.set(false) }
    }

    private fun copyResponse(c: HttpsURLConnection, file: File, expected: Long, initial: Long, append: Boolean, token: Long) {
        var received = initial
        var lastBytes = received
        var lastTime = System.currentTimeMillis()
        BufferedInputStream(c.inputStream, BUFFER_BYTES).use { input ->
            BufferedOutputStream(FileOutputStream(file, append), BUFFER_BYTES).use { output ->
                val buffer = ByteArray(BUFFER_BYTES)
                while (true) {
                    ensureActive(token)
                    val count = input.read(buffer)
                    if (count < 0) break
                    received += count
                    activeReceived.set(received)
                    if (received > expected || received > MAX_APK_BYTES) throw IOException("Update is too large")
                    output.write(buffer, 0, count)
                    val now = System.currentTimeMillis()
                    if (received - lastBytes >= PROGRESS_BYTES || now - lastTime >= PROGRESS_INTERVAL_MS) {
                        lastBytes = received; lastTime = now
                        publish(mapOf("state" to "downloading", "received" to received, "total" to expected))
                    }
                }
            }
        }
        publish(mapOf("state" to "downloading", "received" to received, "total" to expected))
    }

    private fun verifyDigest(file: File, expected: String?, token: Long) {
        if (expected == null) return
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(BUFFER_BYTES)
            while (true) { ensureActive(token); val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        val actual = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actual.equals(expected, true)) throw IOException("Downloaded update checksum is invalid")
    }

    internal fun validateRequest(url: String, size: Long, sha256: String?, name: String) {
        require(size in 1..MAX_APK_BYTES) { "Update size is invalid" }
        require(sha256?.matches(Regex("[0-9a-fA-F]{64}")) == true) {
            "A verified SHA-256 digest is required for in-app updates"
        }
        require(name.lowercase().endsWith(".apk")) { "Update asset is invalid" }
        requireOfficialInitialUrl(URI(url))
    }

    @Suppress("DEPRECATION")
    private fun verifySigningCertificate(context: Context, apk: File) {
        val packageManager = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val installed = packageManager.getPackageInfo(context.packageName, flags)
        val candidate = packageManager.getPackageArchiveInfo(apk.absolutePath, flags)
            ?: throw IOException("Downloaded update is not a valid APK")
        if (candidate.packageName != context.packageName) {
            throw IOException("Downloaded update belongs to a different application")
        }
        val installedCertificates = signingDigests(installed)
        val candidateCertificates = signingDigests(candidate)
        if (installedCertificates.isEmpty() || candidateCertificates.none(installedCertificates::contains)) {
            throw IOException("Downloaded update signing certificate does not match niraNG")
        }
    }

    @Suppress("DEPRECATION")
    private fun signingDigests(info: PackageInfo): Set<String> {
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = info.signingInfo ?: return emptySet()
            if (signingInfo.hasMultipleSigners()) signingInfo.apkContentsSigners
            else signingInfo.signingCertificateHistory
        } else {
            info.signatures
        }.orEmpty()
        return signatures.mapTo(mutableSetOf()) { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }
    }

    private fun open(url: URL, offset: Long) = (url.openConnection() as HttpsURLConnection).apply {
        requestMethod = "GET"; connectTimeout = CONNECT_TIMEOUT_MS; readTimeout = READ_TIMEOUT_MS
        instanceFollowRedirects = false; useCaches = false
        setRequestProperty("Accept", "application/vnd.android.package-archive")
        setRequestProperty("Accept-Encoding", "identity")
        setRequestProperty("User-Agent", "niraNG-updater/${BuildConfig.VERSION_NAME}")
        if (offset > 0) setRequestProperty("Range", "bytes=$offset-")
    }

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun dir(c: Context) = File(c.cacheDir, "updates").apply { mkdirs() }
    private fun apkFile(c: Context) = File(dir(c), "nirang-update.apk")
    private fun partFile(c: Context) = File(dir(c), "nirang-update.part")
    private fun clearFiles(c: Context) { dir(c).listFiles()?.forEach { if (it.extension in setOf("apk", "part")) it.delete() } }
    private fun ensureActive(token: Long) { if (generation.get() != token) throw DownloadCancelledException() }
    private fun publish(value: Map<String, Any?>) = UpdateDownloadEvents.emit(value)

    private fun requireOfficialInitialUrl(uri: URI) {
        require(uri.scheme.equals("https", true) && uri.host.equals("github.com", true)) { "Update URL is not trusted" }
        require(uri.path.startsWith("/bardia-us/niraNG/releases/download/") && uri.path.endsWith(".apk", true)) { "Not an official niraNG APK" }
    }
    private fun requireAllowedDownloadHost(url: URL) {
        require(url.protocol.equals("https", true) && url.host.lowercase() in ALLOWED_HOSTS) { "Update redirect is not trusted" }
    }

    internal fun compareVersions(left: String, right: String): Int {
        fun parts(v: String) = v.removePrefix("v").substringBefore('+').substringBefore('-').split('.').map { it.toIntOrNull() ?: 0 }
        val a = parts(left); val b = parts(right)
        for (i in 0..2) { val result = a.getOrElse(i) { 0 }.compareTo(b.getOrElse(i) { 0 }); if (result != 0) return result }
        return 0
    }

    private class DownloadCancelledException : IOException()
    private val ALLOWED_HOSTS = setOf("github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com")
}
