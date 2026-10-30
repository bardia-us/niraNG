package dev.nirang.client.cores.singbox

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CancellationException

class SingBoxSocketProtectionTest {
    @Test fun protectFailureCannotBeReportedAsSuccess() {
        assertThrows(IllegalStateException::class.java) { SingBoxSocketProtection.protect(7, {}) { false } }
    }

    @Test fun cancellationRejectsSocketBeforeProtect() {
        var called = false
        assertThrows(CancellationException::class.java) {
            SingBoxSocketProtection.protect(7, { throw CancellationException() }) { called = true; true }
        }
        assertFalse(called)
    }

    @Test fun invalidDescriptorIsNeverForwardedToVpnService() {
        var called = false
        assertThrows(IllegalStateException::class.java) {
            SingBoxSocketProtection.protect(-1, {}) { called = true; true }
        }
        assertFalse(called)
    }
}
