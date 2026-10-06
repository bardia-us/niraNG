package dev.nirang.client.registration

import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** One monotonic budget for status + token renewal, including stalled reads. */
internal class ApiRequestDeadline(
    timeoutMillis: Int,
    private val nanoTime: () -> Long = System::nanoTime,
) {
    private val end = nanoTime() + timeoutMillis.toLong() * 1_000_000L

    init { require(timeoutMillis > 0) }

    fun remainingMillis(): Int {
        val remaining = end - nanoTime()
        if (remaining <= 0) throw SocketTimeoutException("Device access check timed out")
        // HttpURLConnection interprets zero as infinite; round UP.
        return ((remaining + 999_999L) / 1_000_000L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    fun watch(connection: HttpURLConnection): AutoCloseable {
        val cancellation = watchdog.schedule(
            { connection.disconnect() }, remainingMillis().toLong(), TimeUnit.MILLISECONDS,
        )
        return AutoCloseable { cancellation.cancel(false) }
    }

    companion object {
        private val watchdog = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "nirang-api-deadline").apply { isDaemon = true }
        }
    }
}
