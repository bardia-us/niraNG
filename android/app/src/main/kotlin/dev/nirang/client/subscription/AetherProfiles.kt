package dev.nirang.client.subscription

import java.net.URI
import java.net.URLDecoder
import java.util.UUID
import org.json.JSONObject

internal object AetherProfiles {
    const val OWNER_DEFAULT_URI = "aether://?protocol=wg-over-masque&scan=balanced&ip=v4&transport=h2&outer=162.159.199.65%3A443&psiphon=chain&psiphon_mode=auto"
    private val allowed = setOf("protocol","scan","ip","transport","outer","psiphon","psiphon_mode")
    fun defaults(): List<CustomProfile> = listOf(
        fromUri(OWNER_DEFAULT_URI,"builtin_aether_psiphon","Aether · Psiphon"),
        fromUri(OWNER_DEFAULT_URI.replace("psiphon=chain","psiphon=off"),"builtin_aether_plain","Aether"),
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
            "wg-over-masque" -> "wireguard-over-masque"
            else -> throw IllegalArgumentException("Unsupported Aether protocol")
        }
        val config = JSONObject().put("mode",mode).put("scan",params["scan"] ?: "balanced")
            .put("ipFamily",params["ip"] ?: "v4").put("carrier",params["transport"] ?: "h3")
            .put("psiphon",params["psiphon"] ?: "chain").put("psiphonMode",params["psiphon_mode"] ?: "auto")
        params["outer"]?.let { config.put("endpoint",it) }
        val label = name ?: uri.rawFragment?.let(::decode)?.takeIf(String::isNotBlank) ?: "Aether · Psiphon"
        return fromJson(config.toString(),id,label)
    }

    fun fromJson(raw: String, id: String = UUID.randomUUID().toString(), name: String): CustomProfile =
        CustomProfileCodec.fromPrivateJson(JSONObject().put("version",1).put("id",id).put("name",name)
            .put("kind","aether").put("engine","aether").put("payload",raw))
}
