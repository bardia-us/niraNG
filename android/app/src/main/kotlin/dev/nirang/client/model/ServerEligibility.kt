package dev.nirang.client.model

object ServerEligibility {
    fun rejectionReason(server: ServerRecord): String? {
        val normalizedName = server.name.lowercase()
        if (NOTICE_MARKERS.any(normalizedName::contains)) {
            return "This entry is subscription information, not a connectable server"
        }
        val address = server.address.trim().lowercase()
        if (address in NON_CONNECTABLE_ADDRESSES) return "This server address is not connectable"
        if (server.port !in 1..65_535) return "This server port is invalid"
        return null
    }

    private val NOTICE_MARKERS = listOf(
        "هر دفعه آپدیت",
        "هر بار آپدیت",
        "آپدیت کنید",
        "به‌روزرسانی کنید",
        "بروزرسانی کنید",
        "update subscription",
        "update config",
    )
    private val NON_CONNECTABLE_ADDRESSES = setOf("", "0.0.0.0", "::", "localhost")
}
