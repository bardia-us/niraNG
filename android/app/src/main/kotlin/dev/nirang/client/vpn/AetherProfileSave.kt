package dev.nirang.client.vpn

import dev.nirang.client.cores.aether.AetherOptions

/** Owns the save side effect while keeping the bridge result unchanged. */
internal object AetherProfileSave {
    fun <T> save(
        id: String?,
        readPayload: (String) -> String?,
        persist: () -> T,
        activeServerId: () -> String?,
        isActive: () -> Boolean,
        restart: (String) -> Unit,
    ): T {
        val before = id?.let(readPayload)?.let(::connectionValues)
        val result = persist()
        // Read the committed profile and the real service identity after writing:
        // a selected/queued row is not proof this is the currently active VPN.
        if (id != null && before != null && activeServerId() == id && isActive()) {
            val after = readPayload(id)?.let(::connectionValues)
            if (after != null && before != after) restart(id)
        }
        return result
    }

    private fun connectionValues(payload: String): List<Any?> = AetherOptions.parse(payload).let {
        listOf(it.mode,it.psiphon,it.psiphonMode,it.psiphonRegion,it.scan,it.carrier,
            it.ipFamily,it.endpoint,it.keepalive,it.dns,it.startupTimeoutSeconds)
    }
}
