package dev.nirang.client.subscription

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.Base64
import dev.nirang.client.cores.aether.AetherOptions

data class CustomProfile(val id: String, val name: String, val engine: String, val payload: String, val kind: String = "json") {
    fun toPrivateJson(): JSONObject = JSONObject().put("version", 1).put("id", id)
        .put("name", name).put("kind", kind).put("engine", engine).put("payload", payload)
}

object CustomProfileCodec {
    const val PREFIX = "nira-profile://v1/"
    const val MAX_PAYLOAD_BYTES = 256 * 1024
    const val MAX_ENVELOPE_BYTES = 512 * 1024
    fun decode(wire: String): CustomProfile {
        require(wire.startsWith(PREFIX) && wire.length <= PREFIX.length + (MAX_ENVELOPE_BYTES * 4 / 3 + 4)) { "Invalid custom profile envelope" }
        val encoded = wire.substring(PREFIX.length)
        require(encoded.isNotEmpty() && encoded.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }) { "Invalid custom profile encoding" }
        val text = try {
            val bytes = Base64.getUrlDecoder().decode(encoded)
            require(Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) == encoded)
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) { throw IllegalArgumentException("Invalid custom profile encoding") }
        return fromPrivateJson(StrictProfileJson.objectValue(text, MAX_ENVELOPE_BYTES))
    }

    fun fromPrivateJson(json: JSONObject): CustomProfile {
        require(json.opt("version") is Int && json.optInt("version") == 1 && json.opt("kind") in setOf("json", "aether")) { "Unsupported custom profile version or kind" }
        require(json.keys().asSequence().all { it in setOf("version", "id", "name", "kind", "engine", "payload") }) { "Unknown custom profile envelope field" }
        fun field(key: String): String = (json.opt(key) as? String) ?: throw IllegalArgumentException("Missing custom profile field")
        val id = field("id"); val name = field("name"); val engine = field("engine"); val payload = field("payload")
        val kind = field("kind")
        require(Regex("[A-Za-z0-9_-]{1,80}").matches(id)) { "Invalid custom profile ID" }
        require(name.isNotBlank() && name.toByteArray(Charsets.UTF_8).size <= 300 && name.none { it.code < 32 || it == '\u007f' }) { "Invalid custom profile name" }
        val config = StrictProfileJson.objectValue(payload, MAX_PAYLOAD_BYTES)
        if (kind == "aether") {
            require(engine == "aether") { "Custom profile engine does not match its configuration" }
            AetherOptions.parse(payload)
        } else {
            require(engine == detectEngine(config)) { "Custom profile engine does not match its configuration" }
        }
        return CustomProfile(id, name, engine, payload, kind)
    }

    internal fun detectEngine(config: JSONObject): String {
        var xray = false; var sing = false; var count = 0
        for (key in listOf("outbounds", "endpoints")) {
            if (!config.has(key)) continue
            val nodes = config.optJSONArray(key) ?: throw IllegalArgumentException("Invalid custom profile connections")
            for (i in 0 until nodes.length()) {
                val node = nodes.optJSONObject(i) ?: throw IllegalArgumentException("Invalid custom profile connection")
                val protocol = node.opt("protocol"); val type = node.opt("type")
                if (protocol is String && protocol.isNotBlank() && !node.has("type") && key == "outbounds") xray = true
                else if (type is String && type.isNotBlank() && !node.has("protocol")) sing = true
                else throw IllegalArgumentException("Unknown custom profile engine")
                count++
            }
        }
        require(count > 0 && xray != sing) { "Ambiguous or empty custom profile engine" }
        // Even unused opposite-engine inbound syntax is not silently accepted.
        config.optJSONArray("inbounds")?.let { nodes ->
            for (i in 0 until nodes.length()) {
                val node = nodes.optJSONObject(i) ?: throw IllegalArgumentException("Invalid custom profile inbound")
                require(if (xray) node.opt("protocol") is String && !node.has("type") else node.opt("type") is String && !node.has("protocol")) { "Mixed custom profile engines" }
            }
        }
        require(!config.has("inbounds") || config.optJSONArray("inbounds") != null) { "Invalid custom profile inbounds" }
        return if (xray) "xray" else "sing-box"
    }
}
