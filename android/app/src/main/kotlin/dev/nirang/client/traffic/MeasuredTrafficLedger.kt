package dev.nirang.client.traffic

import java.util.TimeZone
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONObject

internal class MeasuredTrafficLedger(saved: String?, now: Long, zone: TimeZone) {
    private var day = day(now, zone)
    private var month = day.take(7)
    private var todayBytes = 0L
    private var monthBytes = 0L
    private var observed = false
    private var todayPartial = true
    private var monthPartial = true
    private var active = false
    private var available = false
    private var lastSample = now
    private var zoneId = zone.id

    init {
        if (saved != null) runCatching {
            val json = JSONObject(saved)
            require(json.getInt("version") == 1)
            day = json.getString("day")
            month = json.getString("month")
            todayBytes = json.getLong("todayBytes").also { require(it >= 0) }
            monthBytes = json.getLong("monthBytes").also { require(it >= 0) }
            observed = json.getBoolean("observed")
            todayPartial = json.getBoolean("todayPartial")
            monthPartial = json.getBoolean("monthPartial")
            lastSample = json.getLong("lastSample")
            zoneId = json.getString("zone")
            available = json.getBoolean("available")
            val abandoned = json.getBoolean("active")
            rotate(now, zone)
            if (abandoned || zoneId != zone.id || now < lastSample) {
                // The process died before its final drain, or the calendar moved.
                todayPartial = true
                monthPartial = true
            }
        }.onFailure {
            day = day(now, zone)
            month = day.take(7)
            todayBytes = 0
            monthBytes = 0
            observed = false
            todayPartial = true
            monthPartial = true
            available = false
        }
    }

    fun begin(now: Long, zone: TimeZone) {
        rotate(now, zone)
        if (zoneId != zone.id || now < lastSample) {
            todayPartial = true
            monthPartial = true
        }
        active = true
        lastSample = now
        zoneId = zone.id
    }

    fun record(raw: String?, now: Long, zone: TimeZone) {
        if (!active) return
        rotate(now, zone)
        val bytes = raw?.let(::parseDelta)
        if (bytes == null) {
            available = false
            todayPartial = true
            monthPartial = true
            return
        }
        observed = true
        available = true
        val oldDay = day(lastSample, zone)
        val stableClock = now >= lastSample && zoneId == zone.id
        // Reset-on-read counters have no per-byte timestamps. A boundary-spanning
        // delta cannot honestly be assigned to either date. Keep a lower bound.
        if (stableClock && oldDay == day) todayBytes = add(todayBytes, bytes)
        else if (bytes != 0L || !stableClock) todayPartial = true
        if (stableClock && oldDay.take(7) == month) monthBytes = add(monthBytes, bytes)
        else if (bytes != 0L || !stableClock) monthPartial = true
        lastSample = now
        zoneId = zone.id
    }

    fun end(now: Long, zone: TimeZone) {
        rotate(now, zone)
        active = false
    }

    fun snapshot(now: Long, zone: TimeZone): Map<String, Any?> {
        rotate(now, zone)
        val previousDay = day(lastSample, zone)
        val clockChanged = zoneId != zone.id || now < lastSample
        return mapOf(
            "todayBytes" to todayBytes.takeIf { observed },
            "monthBytes" to monthBytes.takeIf { observed },
            "todayPartial" to (todayPartial || clockChanged || active && previousDay != day),
            "monthPartial" to (monthPartial || clockChanged || active && previousDay.take(7) != month),
            "available" to available,
            "day" to day,
            "month" to month,
            "timeZone" to zone.id,
        )
    }

    fun encode(): String = JSONObject().apply {
        put("version", 1)
        put("day", day)
        put("month", month)
        put("todayBytes", todayBytes)
        put("monthBytes", monthBytes)
        put("observed", observed)
        put("todayPartial", todayPartial)
        put("monthPartial", monthPartial)
        put("active", active)
        put("available", available)
        put("lastSample", lastSample)
        put("zone", zoneId)
    }.toString()

    private fun rotate(now: Long, zone: TimeZone) {
        val current = day(now, zone)
        if (day != current) {
            day = current
            todayBytes = 0
            todayPartial = false
        }
        if (month != current.take(7)) {
            month = current.take(7)
            monthBytes = 0
            monthPartial = false
        }
    }

    private fun day(now: Long, zone: TimeZone): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = zone }.format(Date(now))

    private fun add(left: Long, right: Long): Long =
        if (Long.MAX_VALUE - left < right) Long.MAX_VALUE else left + right

    private fun parseDelta(raw: String): Long? {
        var total = 0L
        for (row in raw.split(';').filter { it.isNotEmpty() }) {
            val fields = row.split(',')
            if (fields.size != 3) return null
            // DNS routing can dispatch again through proxy/direct; including its
            // own dns-out counter would count those payloads twice. Blocked
            // traffic never traverses a network outbound.
            if (fields[0] !in setOf("proxy", "direct")) continue
            if (fields[1] !in setOf("uplink", "downlink")) return null
            val value = fields[2].toLongOrNull()?.takeIf { it >= 0 } ?: return null
            if (Long.MAX_VALUE - total < value) return null
            total += value
        }
        return total
    }
}
