package dev.nirang.client.vpn

import android.content.Context
import dev.nirang.client.model.ServerRecord
import dev.nirang.client.settings.NativeSettings
import dev.nirang.client.subscription.CustomXrayConfig
import dev.nirang.client.cores.aether.AetherSession
import dev.nirang.client.cores.singbox.NativeSingBox
import dev.nirang.client.xray.XrayConfigBuilder

internal object ConnectionPreflight {
    fun validate(context:Context,server:ServerRecord) {
        val settings=NativeSettings(context)
        val profile=server.customProfile
        CustomCoreSwitchPolicy.validate(profile?.engine,
            dev.nirang.client.xray.XrayCore.isRunning() || NativeSingBox.isRunning())
        when(profile?.engine) {
            null -> XrayConfigBuilder.buildProbeConfig(server,settings)
            "xray" -> CustomXrayConfig.prepare(profile.payload,settings.connectionMode == "vpn")
            "sing-box" -> {
                require(settings.connectionMode == "vpn") { "Full sing-box profiles require VPN mode" }
                NativeSingBox.validate(profile.payload)
            }
            "aether" -> AetherSession(context).validate(profile.payload)
            else -> error("Unsupported connection engine")
        }
    }
}
