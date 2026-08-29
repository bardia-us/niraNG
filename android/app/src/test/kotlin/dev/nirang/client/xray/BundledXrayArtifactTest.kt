package dev.nirang.client.xray

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BundledXrayArtifactTest {
    @Test
    fun `pinned PattN core artifact and release ABIs are bundled`() {
        val aar = File(checkNotNull(System.getProperty("nirang.libv2ray.aar")))
        assertTrue("Bundled libv2ray AAR is missing", aar.isFile)
        assertEquals(EXPECTED_SHA256, sha256(aar))

        ZipFile(aar).use { zip ->
            assertTrue(zip.getEntry("classes.jar") != null)
            REQUIRED_ABIS.forEach { abi ->
                assertTrue("Missing native ABI $abi", zip.getEntry("jni/$abi/libgojni.so") != null)
            }
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02X".format(it) }
    }

    private companion object {
        const val EXPECTED_SHA256 = "F52AE053281B9C3E5F01CAB1C92B6AE7D750B05A12BF39B6B3649BF931A570DA"
        val REQUIRED_ABIS = listOf("arm64-v8a", "armeabi-v7a", "x86_64")
    }
}
