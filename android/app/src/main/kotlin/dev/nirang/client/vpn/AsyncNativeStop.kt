package dev.nirang.client.vpn

import java.util.concurrent.Executors

/** Process termination may wait for child processes; lifecycle/UI callbacks only detach ownership. */
internal object AsyncNativeStop {
    private val worker = Executors.newCachedThreadPool { task ->
        Thread(task, "nirang-native-cancel").apply { isDaemon = true }
    }
    fun execute(stop: () -> Unit) { worker.execute { runCatching(stop) } }
}
