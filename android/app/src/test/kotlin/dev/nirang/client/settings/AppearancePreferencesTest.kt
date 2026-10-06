package dev.nirang.client.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AppearancePreferencesTest {
    @Test
    fun `appearance updates preserve validated strings and ignore unrelated keys`() {
        assertEquals(
            mapOf("accentColor" to "blue", "darkCanvas" to "oled", "feedbackMode" to "sound"),
            NativeSettings.validatedAppearance(mapOf(
                "accentColor" to "blue", "darkCanvas" to "oled", "feedbackMode" to "sound",
                "language" to "fa",
            )),
        )
    }

    @Test
    fun `invalid and null preference updates are rejected before writing`() {
        for (key in listOf("accentColor", "darkCanvas", "feedbackMode")) {
            for (invalid in listOf(null, true, 7, "unknown")) {
                val result = runCatching {
                    NativeSettings.validatedAppearance(mapOf("accentColor" to "rose", key to invalid))
                }
                assertTrue("$key=$invalid must reject the update", result.exceptionOrNull() is IllegalArgumentException)
            }
        }
    }

    @Test
    fun `omitted appearance values add no preference writes`() {
        assertEquals(emptyMap<String, String>(), NativeSettings.validatedAppearance(mapOf("language" to "fa")))
    }
}
