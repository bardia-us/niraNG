package dev.nirang.client.traffic

import android.content.Context
import java.util.TimeZone

/** One process-wide ledger, shared by the VPN core and the read-only UI bridge. */
internal class MeasuredTrafficRepository private constructor(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences("nirang_measured_traffic_v1", Context.MODE_PRIVATE)
    private val ledger = MeasuredTrafficLedger(preferences.getString("ledger", null), System.currentTimeMillis(), TimeZone.getDefault())
    private var persistenceHealthy = true

    @Synchronized fun begin() {
        ledger.begin(System.currentTimeMillis(), TimeZone.getDefault())
        persist()
    }

    @Synchronized fun record(raw: String?) {
        ledger.record(raw, System.currentTimeMillis(), TimeZone.getDefault())
        persist()
    }

    @Synchronized fun end() {
        ledger.end(System.currentTimeMillis(), TimeZone.getDefault())
        persist()
    }

    @Synchronized fun snapshot(): Map<String, Any?> =
        ledger.snapshot(System.currentTimeMillis(), TimeZone.getDefault()).toMutableMap().apply {
            if (!persistenceHealthy) {
                put("available", false)
                put("todayPartial", true)
                put("monthPartial", true)
            }
        }

    private fun persist() {
        // Runs on the core worker, never Flutter's main thread. A synchronous
        // checkpoint also preserves the active-session marker on process death.
        persistenceHealthy = runCatching { preferences.edit().putString("ledger", ledger.encode()).commit() }.getOrDefault(false)
    }

    companion object {
        @Volatile private var instance: MeasuredTrafficRepository? = null
        fun get(context: Context): MeasuredTrafficRepository = instance ?: synchronized(this) {
            instance ?: MeasuredTrafficRepository(context).also { instance = it }
        }
    }
}
