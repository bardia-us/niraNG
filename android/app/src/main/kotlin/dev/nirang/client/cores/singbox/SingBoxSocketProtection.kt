package dev.nirang.client.cores.singbox

internal object SingBoxSocketProtection {
    fun protect(fd: Int, assertCurrent: () -> Unit, protect: (Int) -> Boolean) {
        assertCurrent()
        check(fd >= 0) { "Invalid sing-box socket descriptor" }
        check(protect(fd)) { "Android refused sing-box socket protection" }
        assertCurrent()
    }
}
