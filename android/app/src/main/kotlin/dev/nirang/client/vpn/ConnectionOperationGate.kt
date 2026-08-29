package dev.nirang.client.vpn

import java.util.concurrent.atomic.AtomicLong

/** Invalidates callbacks from an older connect/reconnect after a user disconnect. */
internal class ConnectionOperationGate {
    private val generation = AtomicLong(0)

    fun begin(): Long = generation.incrementAndGet()

    fun cancel(): Long = generation.incrementAndGet()

    fun isCurrent(token: Long): Boolean = generation.get() == token
}
