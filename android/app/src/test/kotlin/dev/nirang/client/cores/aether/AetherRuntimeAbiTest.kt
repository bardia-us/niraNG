package dev.nirang.client.cores.aether

import org.junit.Assert.*
import org.junit.Test

class AetherRuntimeAbiTest {
    @Test fun `32 bit install on 64 bit phone uses its actual process ABI`() {
        assertEquals("armeabi-v7a", AetherRuntimeAbi.choose(false, listOf("armeabi-v7a"),
            listOf("arm64-v8a"), setOf("arm64-v8a", "armeabi-v7a")))
        assertEquals("arm64-v8a", AetherRuntimeAbi.choose(true, listOf("armeabi-v7a"),
            listOf("arm64-v8a"), setOf("arm64-v8a", "armeabi-v7a")))
        assertNull(AetherRuntimeAbi.choose(false, listOf("x86"), listOf("x86_64"), setOf("x86_64")))
    }
}
