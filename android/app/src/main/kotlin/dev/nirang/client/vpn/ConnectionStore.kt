package dev.nirang.client.vpn

import dev.nirang.client.bridge.NativeEvents
import dev.nirang.client.model.ConnectionState

object ConnectionStore {
    private val lock = Any()
    private var state = ConnectionState.DISCONNECTED
    private var serverId: String? = null
    private var serverName: String? = null
    private var publicIp: String? = null
    private var publicCountry: String? = null
    private var error: String? = null

    fun transition(next: ConnectionState, id: String? = serverId, name: String? = serverName, message: String? = null) {
        synchronized(lock) {
            state = next
            serverId = id
            serverName = name
            error = message?.take(240)
            if (next in setOf(ConnectionState.PREPARING, ConnectionState.CONNECTING, ConnectionState.SWITCHING)) {
                publicIp = null
                publicCountry = null
            }
            if (next == ConnectionState.DISCONNECTED) {
                publicIp = null
                publicCountry = null
                serverId = null
                serverName = null
            }
        }
        NativeEvents.emit("connectionState", snapshot())
    }

    fun setPublicIp(ip: String?, country: String?) {
        synchronized(lock) {
            publicIp = ip
            publicCountry = country
        }
        NativeEvents.emit("connectionState", snapshot())
    }

    fun state(): ConnectionState = synchronized(lock) { state }

    fun snapshot(): Map<String, Any?> = synchronized(lock) {
        mapOf(
            "state" to state.wireValue,
            "serverId" to serverId,
            "serverName" to serverName,
            "publicIp" to publicIp,
            "publicCountry" to publicCountry,
            "error" to error,
        )
    }
}
