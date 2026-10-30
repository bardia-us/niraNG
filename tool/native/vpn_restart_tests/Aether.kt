package dev.nirang.client.cores.aether
import android.content.Context
class AetherSession(context: Context, onProgress: (String)->Unit) {
    fun prepare(payload: String, upstream: Int) { prepareHook?.invoke() }
    fun stop() { stopHook?.invoke() }
    companion object {
        @Volatile var prepareHook: (()->Unit)? = null
        @Volatile var stopHook: (()->Unit)? = null
    }
}
