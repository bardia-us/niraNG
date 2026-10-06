package dev.nirang.client.vpn

import java.util.concurrent.Executors
import java.util.concurrent.ExecutorService
import java.util.concurrent.RejectedExecutionException

/** Owns the service's queued lifecycle work and optional network diagnostics. */
internal class VpnTaskRunner {
    private val lifecycle = Executors.newSingleThreadExecutor()
    private val diagnostics = Executors.newSingleThreadExecutor()

    fun submit(action: () -> Unit): Boolean = enqueue(lifecycle, action)

    fun submitDiagnostic(action: () -> Unit): Boolean = enqueue(diagnostics, action)

    private fun enqueue(executor: ExecutorService, action: () -> Unit): Boolean = try {
        executor.execute(action)
        true
    } catch (_: RejectedExecutionException) {
        false
    }

    fun shutdownNow() {
        lifecycle.shutdownNow()
        diagnostics.shutdownNow()
    }
}
