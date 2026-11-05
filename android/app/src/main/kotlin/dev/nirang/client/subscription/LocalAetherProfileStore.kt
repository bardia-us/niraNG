package dev.nirang.client.subscription

import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** Presets only; native identity/certificate files never enter this store. */
internal class LocalAetherProfileStore(
    private val file: File,
    private val read: (File) -> String,
    private val write: (File,String) -> Unit,
) {
    fun load(): List<CustomProfile> {
        if (!file.exists()) return AetherProfiles.defaults()
        val root = StrictProfileJson.objectValue(read(file),1024*1024)
        require(root.optInt("version") == 1) { "Unsupported local Aether profile storage" }
        val profiles = root.getJSONArray("profiles")
        require(profiles.length() <= 100) { "Too many local Aether profiles" }
        val result = (0 until profiles.length()).map { CustomProfileCodec.fromPrivateJson(profiles.getJSONObject(it)) }
        require(result.all { it.kind == "aether" } && result.map { it.id }.toSet().size == result.size) { "Invalid local Aether profiles" }
        return if (result.none { it.id == "builtin_wireguard_irancell" } && result.size < 100) result + AetherProfiles.irancellPreset() else result
    }

    fun save(id: String?, name: String, raw: String): CustomProfile {
        val existing=load().toMutableList()
        if(id != null) require(existing.any { it.id == id }) { "Local Aether profile not found" }
        val candidate=AetherProfiles.fromJson(raw,id ?: java.util.UUID.randomUUID().toString(),name)
        val index=existing.indexOfFirst { it.id == candidate.id }
        if(index >= 0) existing[index]=candidate else { require(existing.size < 100) { "Too many local Aether profiles" };existing.add(candidate) }
        val document=JSONObject().put("version",1).put("profiles",JSONArray(existing.map(CustomProfile::toPrivateJson)))
        write(file,document.toString())
        return candidate
    }
}
