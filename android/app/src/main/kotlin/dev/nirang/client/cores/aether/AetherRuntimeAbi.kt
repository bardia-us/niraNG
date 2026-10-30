package dev.nirang.client.cores.aether

internal object AetherRuntimeAbi {
    fun choose(is64Bit: Boolean, supported32: List<String>, supported64: List<String>, packaged: Set<String>): String? =
        (if (is64Bit) supported64 else supported32).firstOrNull { it in packaged }
}
