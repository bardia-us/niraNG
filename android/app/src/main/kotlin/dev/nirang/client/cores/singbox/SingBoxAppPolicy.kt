package dev.nirang.client.cores.singbox

internal object SingBoxAppPolicy {
    data class Rules(val allowed: Set<String>, val disallowed: Set<String>)
    fun resolve(included: Set<String>, excluded: Set<String>, ownPackage: String): Rules {
        require(included.isEmpty() || excluded.isEmpty()) { "TUN include_package and exclude_package cannot be combined" }
        if (included.isNotEmpty()) {
            val allowed = included - ownPackage
            require(allowed.isNotEmpty()) { "sing-box include_package must contain an app other than niraNG" }
            return Rules(allowed, emptySet())
        }
        return Rules(emptySet(), excluded + ownPackage)
    }
}
