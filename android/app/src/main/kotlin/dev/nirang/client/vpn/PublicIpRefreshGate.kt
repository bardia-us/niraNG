package dev.nirang.client.vpn

/** Serializes IP diagnostics and limits manual requests using monotonic time. */
internal class PublicIpRefreshGate<T>(private val clock: () -> Long) {
    internal class Request<T>(
        val payload: T,
        val manual: Boolean,
        val previousManualStart: Long?,
        val revision: Long,
    )
    private var active: Request<T>? = null
    private var pendingAutomatic: Request<T>? = null
    private var revision = 0L
    private var lastManualStart: Long? = null

    @Synchronized
    fun tryBegin(manual: Boolean, payload: T): Request<T>? {
        val current = active
        if (current != null) {
            if (!manual && (current.revision != revision || current.payload != payload)) {
                pendingAutomatic = Request(payload, false, lastManualStart, revision)
            }
            return null
        }
        val now = clock()
        if (manual && lastManualStart?.let { now - it < 5_000L } == true) return null
        val request = Request(payload, manual, lastManualStart, revision)
        if (manual) lastManualStart = now
        active = request
        return request
    }

    @Synchronized
    fun complete(request: Request<T>): Request<T>? {
        if (active !== request) return null
        val next = pendingAutomatic?.takeIf { it.revision == revision }
        pendingAutomatic = null
        active = next
        return next
    }

    @Synchronized
    fun abandon(request: Request<T>): Request<T>? {
        if (active !== request) return null
        if (request.manual) lastManualStart = request.previousManualStart
        return complete(request)
    }

    @Synchronized
    fun invalidate() {
        revision++
        pendingAutomatic = null
    }

    @Synchronized
    fun commitIfCurrent(request: Request<T>, action: () -> Boolean): Boolean =
        active === request && request.revision == revision && action()
}
