package dev.nirang.client.vpn

/** Shared ownership for an editor preparation and explicit VPN stop commands.
 * Disconnected is a valid starting state; only an explicit cancel invalidates it. */
internal class AetherPreparationCoordinator {
    private val lock = Any()
    private var generation = 0L
    private var active: Long? = null
    private var stopSession: (() -> Unit)? = null

    fun begin(): Long = synchronized(lock) {
        check(active == null) { "Aether preparation is already running" }
        (++generation).also { active = it }
    }

    fun current(token: Long): Boolean = synchronized(lock) { active == token }

    fun install(token: Long, stop: () -> Unit): Boolean {
        val accepted = synchronized(lock) {
            if (active == token && stopSession == null) {
                stopSession = stop
                true
            } else false
        }
        if (!accepted) stop()
        return accepted
    }

    fun finish(token: Long) {
        val stop = synchronized(lock) {
            if (active != token) null else {
                active = null
                stopSession.also { stopSession = null }
            }
        }
        stop?.invoke()
    }

    fun cancel(dispatch: ((() -> Unit) -> Unit) = { it() }) {
        val stop = synchronized(lock) {
            generation++
            active = null
            stopSession.also { stopSession = null }
        }
        stop?.let(dispatch)
    }

    companion object {
        val shared = AetherPreparationCoordinator()
    }
}
