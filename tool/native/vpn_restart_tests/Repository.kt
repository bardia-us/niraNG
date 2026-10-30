package dev.nirang.client.subscription
import android.content.Context
import java.util.concurrent.ConcurrentHashMap
class Profile(val engine: String, val payload: String)
class Target(val id: String, val name: String, val customProfile: Profile? = null)
class SubscriptionRepository(context: Context) {
    fun server(id: String): Target? = servers[id]
    fun select(id: String) { selected = id;onSelect?.invoke(id) }
    fun safeServers(): List<String> = servers.keys.toList()
    companion object {
        val servers = ConcurrentHashMap<String,Target>()
        @Volatile var selected: String? = null
        @Volatile var onSelect: ((String)->Unit)? = null
    }
}
