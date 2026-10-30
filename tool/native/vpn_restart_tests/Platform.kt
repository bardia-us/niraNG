package dev.nirang.client.vpn
import android.content.Context
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.subscription.Target
import java.util.concurrent.CopyOnWriteArrayList
object ConnectionStore {
    @Volatile private var status = ConnectionState.DISCONNECTED
    @Volatile private var serverId: String? = null
    fun transition(state: ConnectionState, id: String? = null, name: String? = null, message: String? = null) { status = state;serverId = id }
    fun state(): ConnectionState = status
    fun snapshot(): Map<String,Any?> = mapOf("serverId" to serverId)
}
object ConnectionPreflight {
    @Volatile var rejected: String? = null
    val validated = CopyOnWriteArrayList<String>()
    fun validate(context: Context, target: Target) { validated += target.id;check(target.id != rejected) }
}
object NirangVpnService {
    val starts = CopyOnWriteArrayList<String>()
    val stops = CopyOnWriteArrayList<Long>()
    @Volatile var activeId: String? = null
    @Volatile var stopHook: ((Long)->Unit)? = null
    fun activeServerId(): String? = activeId
    fun stopForRestart(context: Context, generation: Long, id: String, name: String) {
        stops += generation
        stopHook?.invoke(generation) ?: VpnRestartCoordinator.onServiceStopped(generation)
    }
    fun stopPreservingError(context: Context) { activeId = null }
    fun start(context: Context, id: String, allowFallback: Boolean) {
        starts += id;activeId = id
        ConnectionStore.transition(ConnectionState.CONNECTED,id,id)
    }
}
