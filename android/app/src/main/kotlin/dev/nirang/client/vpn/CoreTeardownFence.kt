package dev.nirang.client.vpn

import java.util.concurrent.CancellationException
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/** A process-wide barrier between an old service's asynchronous close and the next startup. */
internal class CoreTeardownFence {
    private val gate=Any()
    private val worker=Executors.newSingleThreadExecutor { task -> Thread(task,"nirang-core-stop").apply { isDaemon=true } }
    private var latest=CompletableFuture.completedFuture(Unit)

    fun schedule(close: () -> Unit) = synchronized(gate) {
        val completed=CompletableFuture<Unit>()
        latest=completed
        worker.execute { try { close() } finally { completed.complete(Unit) } }
    }

    /** Called only on a lifecycle worker. Polling permits cancellation even if native close stalls. */
    fun awaitPreviousStops(current: () -> Boolean) {
        while(true) {
            if(!current() || Thread.currentThread().isInterrupted) throw CancellationException("Connection cancelled")
            val pending=synchronized(gate) { latest }
            try { pending.get(100,TimeUnit.MILLISECONDS) } catch (_:TimeoutException) { continue }
            if(!current()) throw CancellationException("Connection cancelled")
            if(synchronized(gate) { latest === pending }) return
        }
    }

    internal fun shutdown() { worker.shutdown() }
    companion object { val shared=CoreTeardownFence() }
}
