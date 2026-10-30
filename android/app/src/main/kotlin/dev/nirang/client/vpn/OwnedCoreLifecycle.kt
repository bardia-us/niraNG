package dev.nirang.client.vpn

/** Native start/close are serialized, while UI state reads never wait for native teardown. */
internal class OwnedCoreLifecycle {
    private val gate = Any()
    @Volatile private var owner: Any? = null
    val isRunning: Boolean get() = owner != null

    fun start(expectedOwner: Any, current: () -> Boolean = { true }, launch: () -> Unit) = synchronized(gate) {
        if(!current() || Thread.currentThread().isInterrupted) throw java.util.concurrent.CancellationException("Connection cancelled")
        check(owner == null) { "Connection core is already running" }
        launch()
        owner = expectedOwner
    }

    fun stop(expectedOwner: Any, close: () -> Unit) = synchronized(gate) {
        if (owner !== expectedOwner) return@synchronized
        owner = null
        close()
    }

    fun <T> serialized(action: () -> T): T = synchronized(gate) { action() }
}
