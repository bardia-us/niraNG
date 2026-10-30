package dev.nirang.client.xray

import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipFile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.json.JSONObject

class BundledXrayArtifactTest {
    @Test
    fun `pinned PattN core artifact and release ABIs are bundled`() {
        val aar = File(checkNotNull(System.getProperty("nirang.libv2ray.aar")))
        assertTrue("Bundled libv2ray AAR is missing", aar.isFile)
        assertEquals(EXPECTED_SHA256, sha256(aar))
        val provenance = JSONObject(File(aar.parentFile,"libv2ray-build.json").readText())
        assertEquals("3115a981a8b6", provenance.getString("coreCommit"))
        assertEquals("go1.26.7", provenance.getString("go"))
        assertEquals("f52ae053281b9c3e5f01cab1c92b6ae7d750b05a12bf39b6b3649bf931a570da", provenance.getString("originalSha256"))
        assertEquals(false, provenance.getBoolean("tlsCompatibilityOverride"))
        assertEquals(EXPECTED_SHA256, provenance.getString("sha256").uppercase())

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
        const val EXPECTED_SHA256 = "821E68750C7C903AB79D0036AF7A433F5926E776F02CA1D9DF33B2E21DCB234A"
        val REQUIRED_ABIS = listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
    }
}
