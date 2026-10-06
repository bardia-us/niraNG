package dev.nirang.client.vpn

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnTaskRunnerTest {
    @Test
    fun `unresponsive public IP endpoint cannot delay restart stop work`() {
        val runner = VpnTaskRunner()
        val diagnosticStarted = CountDownLatch(1)
        val releaseDiagnostic = CountDownLatch(1)
        val serviceStopped = CountDownLatch(1)
        try {
            runner.submitDiagnostic {
                diagnosticStarted.countDown()
                releaseDiagnostic.await()
            }
            assertTrue(diagnosticStarted.await(2, TimeUnit.SECONDS))

            runner.submit { serviceStopped.countDown() }

            assertTrue("Restart stop was blocked by public IP lookup", serviceStopped.await(2, TimeUnit.SECONDS))
        } finally {
            releaseDiagnostic.countDown()
            runner.shutdownNow()
        }
    }

    @Test
    fun `late network callbacks after service destruction are dropped`() {
        val runner = VpnTaskRunner()
        runner.shutdownNow()

        assertFalse(runner.submit { error("Destroyed service must not run callbacks") })
        assertFalse(runner.submitDiagnostic { error("Destroyed service must not run diagnostics") })
    }
}
