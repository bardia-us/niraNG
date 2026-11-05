package dev.nirang.client.cores.aether

/** Only validated numeric gateway addresses escape the private native output stream. */
internal object AetherEndpoint {
    fun parse(mode: String, line: String): Map<String,String>? {
        if (line.length > 4096) return null
        val expression = when(mode) {
            "wireguard" -> "(?:selected WireGuard endpoint|using cloudflare edge) (\\S+)"
            "warp-in-warp" -> "using cloudflare edge (\\S+) \\(outer\\) and (\\S+) \\(inner\\)"
            "masque-in-masque" -> "masque-in-masque ready: (\\S+) \\(outer\\) and (\\S+) \\(inner\\)"
            "wireguard-over-masque" -> "gool ready: masque (\\S+) carries wireguard (\\S+)"
            else -> "(?:selected MASQUE gateway|using cloudflare edge) (\\S+)"
        }
        val found=Regex(expression).find(line) ?: return null
        return runCatching {
            fun address(raw:String):String {
                val value=if (!raw.startsWith("[") && raw.count { it == ':' } > 1) "[${raw.substringBeforeLast(':')}]:${raw.substringAfterLast(':')}" else raw
                AetherOptions.parse(org.json.JSONObject().put("endpoint",value).toString())
                return value
            }
            buildMap { put("endpoint",address(found.groupValues[1])); if(found.groupValues.size>2) put("innerEndpoint",address(found.groupValues[2])) }
        }.getOrNull()
    }
}
