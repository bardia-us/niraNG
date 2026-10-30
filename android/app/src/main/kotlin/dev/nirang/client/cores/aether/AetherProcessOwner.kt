package dev.nirang.client.cores.aether

/** Serializes process ownership while allowing Stop to cancel a blocking start/provision. */
internal class AetherProcessOwner {
    private val lock = Any()
    private var generation = 0L
    private var close: (() -> Unit)? = null

    fun begin(): Long {
        val previous: (() -> Unit)?
        val token: Long
        synchronized(lock) {
            previous = close
            close = null
            token = ++generation
        }
        previous?.invoke()
        return token
    }

    fun install(token: Long, terminate: () -> Unit): Boolean {
        val accepted = synchronized(lock) {
            if (token == generation && close == null) { close = terminate; true } else false
        }
        if (!accepted) terminate()
        return accepted
    }

    fun current(token: Long): Boolean = synchronized(lock) { token == generation }

    fun finish(token: Long) {
        val previous = synchronized(lock) {
            if (token != generation) null else close.also { close = null }
        }
        previous?.invoke()
    }

    fun stop() {
        val previous = synchronized(lock) { ++generation; close.also { close = null } }
        previous?.invoke()
    }
}
