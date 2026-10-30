package dev.nirang.client.traffic

import dev.nirang.client.vpn.CoreTrafficDelta
import org.json.JSONObject

/** Decodes the native inlet snapshot before passing one delta to the ledger. */
internal class XrayInboundTraffic {
    private val delta = CoreTrafficDelta()

    fun sample(raw: String?): String? {
        if (raw == null) return null
        val values = runCatching {
            val snapshot = JSONObject(raw)
            fun counter(key: String): Long {
                val value = snapshot.get(key)
                require(value is Number)
                return value.toString().toLongOrNull()?.takeIf { it >= 0 }
                    ?: throw IllegalArgumentException("Invalid inlet counter")
            }
            counter("uplink") to counter("downlink")
        }.getOrNull() ?: return null
        return delta.sample(values.first,values.second)
    }
}
