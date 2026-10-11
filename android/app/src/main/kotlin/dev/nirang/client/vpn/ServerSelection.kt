package dev.nirang.client.vpn

/** Separates user selection from the asynchronous service/connection state. */
object ServerSelection {
    fun select(
        id: String,
        requiresSwitch: Boolean,
        persist: (String) -> Unit,
        queueSwitch: (String) -> Unit,
    ) {
        // Requested configuration and verified live connection are different
        // states. Publish the choice before the restart queue touches Xray.
        persist(id)
        if (requiresSwitch) queueSwitch(id)
    }
}
