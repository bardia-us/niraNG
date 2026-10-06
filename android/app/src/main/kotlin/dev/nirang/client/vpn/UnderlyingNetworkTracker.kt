package dev.nirang.client.vpn

/** Tracks physical networks; Android validation is a preference, not permission to use VPN. */
internal class UnderlyingNetworkTracker<N> {
    data class Snapshot<N>(val network: N?, val revision: Long)
    private val networks = linkedMapOf<N, Boolean>()
    private var revision = 0L

    @Synchronized
    fun snapshot(): Snapshot<N> = Snapshot(selected(), revision)

    @Synchronized
    fun isCurrent(candidate: Snapshot<N>): Boolean = candidate.network != null && candidate == snapshot()

    @Synchronized
    fun completeReconnect(candidate: Snapshot<N>, connected: () -> Unit): Boolean {
        if (!isCurrent(candidate)) return false
        connected()
        return true
    }

    @Synchronized
    fun update(candidate: N, validated: Boolean): N? {
        val previous = selected()
        networks[candidate] = validated
        return selected().also { if (it != previous) revision++ }
    }

    @Synchronized
    fun remove(candidate: N): N? {
        val previous = selected()
        networks.remove(candidate)
        return selected().also { if (it != previous) revision++ }
    }

    @Synchronized
    fun clear() {
        networks.clear()
        revision++
    }

    private fun selected(): N? = networks.entries.lastOrNull { it.value }?.key ?: networks.keys.lastOrNull()
}
