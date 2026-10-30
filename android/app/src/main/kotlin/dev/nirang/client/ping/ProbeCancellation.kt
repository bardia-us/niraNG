package dev.nirang.client.ping

import java.util.concurrent.CancellationException

/** Cancellation is published before resource closing and never waits on native process termination. */
internal class ProbeCancellation(private val dispatch: ((() -> Unit) -> Unit)) {
    private val lock = Any()
    private var cancelled = false
    private val closers = mutableListOf<() -> Unit>()
    fun check() { synchronized(lock) { if (cancelled || Thread.currentThread().isInterrupted) throw CancellationException("Probe cancelled") } }
    fun own(close: () -> Unit) {
        val reject = synchronized(lock) { if (cancelled) true else { closers += close; false } }
        if (reject) { dispatch(close); throw CancellationException("Probe cancelled") }
    }
    fun cancel() {
        val resources = synchronized(lock) {
            if (cancelled) return
            cancelled = true
            closers.toList().also { closers.clear() }
        }
        resources.asReversed().forEach { close -> dispatch { runCatching(close) } }
    }
}
