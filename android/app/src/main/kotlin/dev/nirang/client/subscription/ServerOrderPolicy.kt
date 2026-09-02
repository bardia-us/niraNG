package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord

internal object ServerOrderPolicy {
    fun apply(preferredIds: List<String>, servers: List<ServerRecord>): List<ServerRecord> {
        if (preferredIds.isEmpty()) return servers
        val byId = servers.associateBy(ServerRecord::id)
        val ordered = ArrayList<ServerRecord>(servers.size)
        val used = HashSet<String>(servers.size)
        preferredIds.distinct().mapNotNull(byId::get).forEach { server ->
            if (used.add(server.id)) ordered += server
        }
        servers.forEach { server -> if (used.add(server.id)) ordered += server }
        return ordered
    }

    fun afterRefresh(
        preferredIds: List<String>,
        previousServers: List<ServerRecord>,
        refreshedServers: List<ServerRecord>,
    ): List<ServerRecord> {
        val previousById = previousServers.associateBy(ServerRecord::id)
        val remaining = refreshedServers.toMutableList()
        val ordered = mutableListOf<ServerRecord>()
        preferredIds.mapNotNull(previousById::get).forEach { previous ->
            val exact = remaining.firstOrNull { refreshed -> sameConfiguration(previous, refreshed) }
            val endpointMatches = remaining.filter { refreshed -> sameEndpoint(previous, refreshed) }
            val match = exact ?: endpointMatches.singleOrNull()
            if (match != null) {
                ordered += match
                remaining.remove(match)
            }
        }

        // Insert genuinely new/changed profiles next to their nearest source
        // neighbour without disturbing the user's relative manual order.
        refreshedServers.forEachIndexed { sourceIndex, server ->
            if (ordered.any { it.id == server.id }) return@forEachIndexed
            val previousAnchor = (sourceIndex - 1 downTo 0)
                .map { refreshedServers[it].id }
                .firstOrNull { id -> ordered.any { it.id == id } }
            val nextAnchor = (sourceIndex + 1 until refreshedServers.size)
                .map { refreshedServers[it].id }
                .firstOrNull { id -> ordered.any { it.id == id } }
            when {
                previousAnchor != null -> ordered.add(ordered.indexOfFirst { it.id == previousAnchor } + 1, server)
                nextAnchor != null -> ordered.add(ordered.indexOfFirst { it.id == nextAnchor }, server)
                else -> ordered += server
            }
        }
        return ordered
    }

    fun move(ids: List<String>, oldIndex: Int, requestedNewIndex: Int): List<String> {
        require(oldIndex in ids.indices) { "Invalid source index" }
        require(requestedNewIndex in 0..ids.size) { "Invalid destination index" }
        val result = ids.toMutableList()
        val item = result.removeAt(oldIndex)
        val destination = if (requestedNewIndex > oldIndex) requestedNewIndex - 1 else requestedNewIndex
        result.add(destination.coerceIn(0, result.size), item)
        return result
    }

    private fun sameConfiguration(first: ServerRecord, second: ServerRecord): Boolean =
        first.protocol.equals(second.protocol, true) &&
            first.address.equals(second.address, true) &&
            first.port == second.port &&
            first.credential == second.credential &&
            first.transport.equals(second.transport, true) &&
            first.security.equals(second.security, true) &&
            first.parameters == second.parameters

    private fun sameEndpoint(first: ServerRecord, second: ServerRecord): Boolean =
        first.protocol.equals(second.protocol, true) &&
            first.address.equals(second.address, true) &&
            first.port == second.port
}
