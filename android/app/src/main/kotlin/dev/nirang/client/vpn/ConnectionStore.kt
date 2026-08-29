package dev.nirang.client.vpn

import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.model.ConnectionState
import java.util.concurrent.CopyOnWriteArraySet

internal data class ConnectionSnapshot(
    val state: ConnectionState,
    val serverId: String?,
    val serverName: String?,
    val publicIp: String?,
    val publicCountry: String?,
    val publicCity: String?,
    val publicIpChecked: Boolean,
    val error: String?,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "state" to state.wireValue,
        "serverId" to serverId,
        "serverName" to serverName,
        "publicIp" to publicIp,
        "publicCountry" to publicCountry,
        "publicCity" to publicCity,
        "publicIpChecked" to publicIpChecked,
        "error" to error,
    )
}

object ConnectionStore {
    private val lock = Any()
    private val listeners = CopyOnWriteArraySet<(ConnectionSnapshot) -> Unit>()
    private var state = ConnectionState.DISCONNECTED
    private var serverId: String? = null
    private var serverName: String? = null
    private var publicIp: String? = null
    private var publicCountry: String? = null
    private var publicCity: String? = null
    private var publicIpChecked = false
    private var error: String? = null

    fun transition(next: ConnectionState, id: String? = serverId, name: String? = serverName, message: String? = null) {
        synchronized(lock) {
            state = next
            serverId = id
            serverName = name
            error = message?.take(240)
            if (
                next in setOf(
                    ConnectionState.PREPARING,
                    ConnectionState.CONNECTING,
                    ConnectionState.RESTARTING,
                    ConnectionState.SWITCHING,
                    ConnectionState.RECONNECTING,
                )
            ) {
                publicIp = null
                publicCountry = null
                publicCity = null
                publicIpChecked = false
            }
            if (next == ConnectionState.DISCONNECTED) {
                publicIp = null
                publicCountry = null
                publicCity = null
                publicIpChecked = false
                serverId = null
                serverName = null
            }
        }
        publish()
    }

    fun beginPublicIpRefresh(expectedServerId: String): Boolean {
        val accepted = synchronized(lock) {
            if (state != ConnectionState.CONNECTED || serverId != expectedServerId) return@synchronized false
            publicIp = null
            publicCountry = null
            publicCity = null
            publicIpChecked = false
            true
        }
        if (accepted) publish()
        return accepted
    }

    fun setPublicIp(expectedServerId: String, ip: String?, country: String?, city: String?): Boolean {
        val accepted = synchronized(lock) {
            if (state != ConnectionState.CONNECTED || serverId != expectedServerId) return@synchronized false
            publicIp = ip
            publicCountry = country
            publicCity = city
            publicIpChecked = true
            true
        }
        if (accepted) publish()
        return accepted
    }

    fun state(): ConnectionState = synchronized(lock) { state }

    internal fun current(): ConnectionSnapshot = synchronized(lock) {
        ConnectionSnapshot(
            state,
            serverId,
            serverName,
            publicIp,
            publicCountry,
            publicCity,
            publicIpChecked,
            error,
        )
    }

    internal fun addListener(listener: (ConnectionSnapshot) -> Unit) {
        listeners += listener
        runCatching { listener(current()) }
    }

    internal fun removeListener(listener: (ConnectionSnapshot) -> Unit) {
        listeners -= listener
    }

    private fun publish() {
        val value = current()
        NativeEvents.emit("connectionState", value.toMap())
        listeners.forEach { listener -> runCatching { listener(value) } }
    }

    fun snapshot(): Map<String, Any?> = current().toMap()
}
