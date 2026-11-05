package dev.nirang.client.subscription

import java.net.URI
import java.net.URLDecoder
import java.util.UUID
import org.json.JSONObject

internal object AetherProfiles {
    fun editorValues(raw: String): Map<String, Any?> {
        val config=StrictProfileJson.objectValue(raw,8192)
        dev.nirang.client.cores.aether.AetherOptions.parse(raw)
        fun value(node: Any?): Any? = when(node) {
            null, JSONObject.NULL -> null
            is JSONObject -> node.keys().asSequence().associateWith { value(node.get(it)) }
            is org.json.JSONArray -> (0 until node.length()).map { value(node.get(it)) }
            else -> node
        }
        return config.keys().asSequence().associateWith { value(config.get(it)) }
    }
    const val OWNER_DEFAULT_URI = "aether://?protocol=wg-over-masque&scan=balanced&ip=v4&transport=h2&outer=162.159.199.65%3A443&psiphon=chain&psiphon_mode=auto"
    private val allowed = setOf("protocol","scan","ip","transport","outer","psiphon","psiphon_mode","inner","fp","fingerprint")
    fun irancellPreset(): CustomProfile = fromUri("aether://?protocol=wg&ip=v4&psiphon=off","builtin_wireguard_irancell","WireGuard | Irancell")
    fun defaults(): List<CustomProfile> = listOf(
        fromUri(OWNER_DEFAULT_URI,"builtin_aether_psiphon","Aether · Psiphon"),
        fromUri(OWNER_DEFAULT_URI.replace("psiphon=chain","psiphon=off"),"builtin_aether_plain","Aether"),
        irancellPreset(),
    )

    fun fromUri(raw: String, id: String = UUID.randomUUID().toString(), name: String? = null): CustomProfile {
        require(raw.length <= 16384) { "Aether link is too large" }
        val uri = try { URI(raw) } catch (_: Exception) { throw IllegalArgumentException("Invalid Aether link") }
        require(uri.scheme == "aether" && uri.rawAuthority.isNullOrEmpty() && uri.rawPath.isNullOrEmpty()) { "Invalid Aether link" }
        fun decode(value: String): String = try { URLDecoder.decode(value.replace("+","%2B"),"UTF-8") }
            catch (_:Exception) { throw IllegalArgumentException("Invalid Aether encoding") }
        val params = linkedMapOf<String,String>()
        for (field in uri.rawQuery.orEmpty().split('&').filter(String::isNotEmpty)) {
            val parts = field.split('=',limit=2)
            val key = decode(parts[0])
            require(key in allowed && key !in params && parts.size == 2) { "Unknown or repeated Aether option" }
            params[key] = decode(parts[1])
        }
        val mode = when(params["protocol"] ?: "masque") {
            "masque" -> "masque"
            "wg", "wireguard" -> "wireguard"
            "wg-over-masque", "wireguard-over-masque" -> "wireguard-over-masque"
            "gool", "warp-in-warp" -> "warp-in-warp"
            "mim", "masque-in-masque" -> "masque-in-masque"
            else -> throw IllegalArgumentException("Unsupported Aether protocol")
        }
        val config = JSONObject().put("mode",mode).put("scan",params["scan"] ?: "balanced")
            .put("ipFamily",params["ip"] ?: "v4").put("carrier",if(mode in setOf("wireguard","warp-in-warp")) "h3" else params["transport"] ?: "h3")
            .put("psiphon",params["psiphon"] ?: "chain").put("psiphonMode",params["psiphon_mode"] ?: "auto")
        params["outer"]?.let { config.put(if(mode in setOf("warp-in-warp","masque-in-masque","wireguard-over-masque")) "outerEndpoint" else "endpoint",it) }
        params["inner"]?.let { config.put("innerEndpoint",it) }
        (params["fp"] ?: params["fingerprint"])?.let { config.put("fingerprint",it) }
        val label = name ?: uri.rawFragment?.let(::decode)?.takeIf(String::isNotBlank) ?: "Aether · Psiphon"
        return fromJson(config.toString(),id,label)
    }

    fun fromJson(raw: String, id: String = UUID.randomUUID().toString(), name: String): CustomProfile =
        CustomProfileCodec.fromPrivateJson(JSONObject().put("version",1).put("id",id).put("name",name)
            .put("kind","aether").put("engine","aether").put("payload",raw))
}
