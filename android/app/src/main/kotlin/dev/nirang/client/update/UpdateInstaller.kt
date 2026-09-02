package dev.nirang.client.update

import android.app.Activity
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean
import javax.net.ssl.HttpsURLConnection

object UpdateInstaller {
    private const val CONNECT_TIMEOUT_MS = 10_000
    private const val READ_TIMEOUT_MS = 20_000
    private const val MAX_APK_BYTES = 250L * 1024 * 1024
    private const val MAX_REDIRECTS = 5
    private val downloading = AtomicBoolean(false)

    fun download(activity: Activity, url: String, expectedSize: Long, sha256: String?): File {
        check(downloading.compareAndSet(false, true)) { "An update download is already running" }
        try {
            require(expectedSize in 1..MAX_APK_BYTES) { "Update size is invalid" }
            sha256?.let { require(it.matches(Regex("[0-9a-fA-F]{64}"))) { "Update digest is invalid" } }
            val initial = URI(url)
            requireOfficialInitialUrl(initial)
            val updateDir = File(activity.cacheDir, "updates").apply { mkdirs() }
            val target = File(updateDir, "nirang-update.apk")
            val temporary = File(updateDir, "nirang-update.part")
            temporary.delete()
            target.delete()

            val digest = MessageDigest.getInstance("SHA-256")
            var current = initial.toURL()
            var redirects = 0
            while (true) {
                val connection = open(current)
                try {
                    val status = connection.responseCode
                    if (status in 300..399) {
                        if (redirects++ >= MAX_REDIRECTS) throw IOException("Too many update redirects")
                        val location = connection.getHeaderField("Location") ?: throw IOException("Update redirect is missing")
                        current = URL(current, location)
                        requireAllowedDownloadHost(current)
                        continue
                    }
                    if (status !in 200..299) throw IOException("Update download failed with HTTP $status")
                    val declared = connection.contentLengthLong
                    if (declared > MAX_APK_BYTES) throw IOException("Update is too large")
                    UpdateDownloadEvents.emit("downloading", 0, expectedSize)
                    connection.inputStream.buffered().use { input ->
                        FileOutputStream(temporary).buffered().use { output ->
                            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                            var received = 0L
                            var lastProgressAt = 0L
                            while (true) {
                                val count = input.read(buffer)
                                if (count < 0) break
                                received += count
                                if (received > MAX_APK_BYTES) throw IOException("Update is too large")
                                output.write(buffer, 0, count)
                                digest.update(buffer, 0, count)
                                if (received - lastProgressAt >= 128 * 1024 || received == expectedSize) {
                                    lastProgressAt = received
                                    UpdateDownloadEvents.emit("downloading", received, expectedSize)
                                }
                            }
                        }
                    }
                    break
                } finally {
                    connection.disconnect()
                }
            }
            if (temporary.length() != expectedSize) throw IOException("Downloaded update size does not match GitHub")
            val actualDigest = digest.digest().joinToString("") { "%02x".format(it) }
            if (sha256 != null && !actualDigest.equals(sha256, true)) throw IOException("Downloaded update checksum is invalid")
            if (!temporary.renameTo(target)) throw IOException("Downloaded update could not be finalized")
            UpdateDownloadEvents.emit("installing", target.length(), target.length())
            return target
        } catch (error: Throwable) {
            UpdateDownloadEvents.emit("failed")
            throw error
        } finally {
            downloading.set(false)
        }
    }

    fun launchInstaller(activity: Activity, apk: File) {
        require(apk.isFile && apk.length() > 0) { "Downloaded APK is unavailable" }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
        )
    }

    private fun open(url: URL): HttpsURLConnection = (url.openConnection() as HttpsURLConnection).apply {
        requestMethod = "GET"
        connectTimeout = CONNECT_TIMEOUT_MS
        readTimeout = READ_TIMEOUT_MS
        instanceFollowRedirects = false
        setRequestProperty("Accept", "application/vnd.android.package-archive")
        setRequestProperty("User-Agent", "niraNG-updater")
    }

    private fun requireOfficialInitialUrl(uri: URI) {
        require(uri.scheme.equals("https", true) && uri.host.equals("github.com", true)) { "Update URL is not trusted" }
        require(uri.path.startsWith("/bardia-us/niraNG/releases/download/") && uri.path.endsWith(".apk", true)) {
            "Update URL is not an official niraNG APK"
        }
    }

    private fun requireAllowedDownloadHost(url: URL) {
        require(url.protocol.equals("https", true)) { "Update redirect is not secure" }
        require(url.host.lowercase() in ALLOWED_DOWNLOAD_HOSTS) { "Update redirect host is not trusted" }
    }

    private val ALLOWED_DOWNLOAD_HOSTS = setOf(
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    )
}
