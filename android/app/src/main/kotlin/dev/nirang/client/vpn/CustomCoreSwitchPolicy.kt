package dev.nirang.client.vpn

/** The bundled Xray binding cannot validate arbitrary JSON without starting it. */
internal object CustomCoreSwitchPolicy {
    fun validate(engine: String?, connectionRunning: Boolean) {
        require(engine != "xray" || !connectionRunning) {
            "Disconnect before starting a full Xray JSON profile"
        }
    }
}
