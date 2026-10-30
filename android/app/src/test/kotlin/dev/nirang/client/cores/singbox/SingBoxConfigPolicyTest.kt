package dev.nirang.client.cores.singbox

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class SingBoxConfigPolicyTest {
    private fun document() = JSONObject("""{
      "inbounds":[{"type":"tun","address":["172.19.0.1/30"],"auto_route":true}],
      "outbounds":[{"type":"direct","tag":"direct"}],
      "route":{"auto_detect_interface":true},
      "dns":{"servers":[{"type":"https","tag":"dns","server":"dns.example","path":"/dns-query"}]}
    }""")

    private fun rejects(config: JSONObject) {
        assertThrows(IllegalArgumentException::class.java) { SingBoxConfigPolicy.validate(config.toString()) }
    }

    @Test fun requiresExplicitSocketProtection() {
        rejects(document().apply { getJSONObject("route").remove("auto_detect_interface") })
        rejects(document().apply { getJSONObject("route").put("auto_detect_interface", false) })
    }

    @Test fun acceptsDnsAndTransportNetworkPathsWithoutRewriting() {
        val raw = document().toString(2)
        SingBoxConfigPolicy.validate(raw)
        SingBoxConfigPolicy.validate(document().apply {
            getJSONArray("outbounds").getJSONObject(0).put("transport", JSONObject("""{"type":"ws","path":"/websocket"}"""))
        }.toString())
    }

    @Test fun rejectsDialerBindingsThatBypassProtect() {
        for (key in listOf("bind_interface", "inet4_bind_address", "inet6_bind_address", "protect_path")) {
            rejects(document().apply { getJSONArray("outbounds").getJSONObject(0).put(key, "unsafe") })
        }
    }

    @Test fun rejectsMissingOrMultipleTunnels() {
        rejects(document().apply { remove("inbounds") })
        rejects(document().apply { getJSONArray("inbounds").put(getJSONArray("inbounds").getJSONObject(0)) })
        rejects(document().apply { getJSONArray("inbounds").getJSONObject(0).put("auto_route", false) })
    }

    @Test fun rejectsFilesystemAndExecutableCapabilitiesBeforeCore() {
        for (key in listOf("certificate_path", "key_path", "executable_path", "initial_path", "config_path")) {
            rejects(document().apply { getJSONArray("outbounds").getJSONObject(0).put(key, "/private/file") })
        }
        rejects(document().put("log", JSONObject().put("output", "/private/file")))
        rejects(document().put("services", org.json.JSONArray().put(JSONObject().put("type", "sshd"))))
        rejects(document().put("experimental", JSONObject().put("debug", JSONObject())))
        rejects(document().apply { getJSONObject("route").put("rule_set", org.json.JSONArray().put(JSONObject().put("type","local").put("path", "/file"))) })
    }

    @Test fun rejectsControlApisEvenOnLoopbackAndNetworkListeners() {
        rejects(document().put("experimental", JSONObject().put("clash_api", JSONObject().put("external_controller", "127.0.0.1:9090"))))
        rejects(document().apply { getJSONArray("inbounds").put(JSONObject("""{"type":"mixed","listen":"0.0.0.0","listen_port":1080}""")) })
        SingBoxConfigPolicy.validate(document().apply { getJSONArray("inbounds").put(JSONObject("""{"type":"mixed","listen":"127.0.0.1","listen_port":1080}""")) }.toString())
    }

    @Test fun rejectsOptionalExecutableAndPrivilegedEndpointTypes() {
        rejects(document().apply { getJSONArray("outbounds").getJSONObject(0).put("type", "tor") })
        rejects(document().apply { getJSONArray("outbounds").getJSONObject(0).put("wifi_ssid", "private") })
        rejects(document().put("endpoints", org.json.JSONArray().put(JSONObject("""{"type":"wireguard","system":true}"""))))
    }
}
