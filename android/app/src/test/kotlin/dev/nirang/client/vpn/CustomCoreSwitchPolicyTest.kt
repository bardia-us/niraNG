package dev.nirang.client.vpn

import org.junit.Assert.assertThrows
import org.junit.Test

class CustomCoreSwitchPolicyTest {
    @Test fun `unvalidated full Xray never interrupts an active core`() {
        assertThrows(IllegalArgumentException::class.java) { CustomCoreSwitchPolicy.validate("xray", true) }
    }
    @Test fun `cold JSON start and native validated or ordinary switching remain available`() {
        CustomCoreSwitchPolicy.validate("xray", false)
        listOf(null, "sing-box", "aether").forEach { CustomCoreSwitchPolicy.validate(it, true) }
    }
}
