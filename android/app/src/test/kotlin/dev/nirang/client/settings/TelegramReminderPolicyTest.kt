package dev.nirang.client.settings

import org.junit.Assert.assertEquals
import org.junit.Test

class TelegramReminderPolicyTest {
    @Test fun `new installation needs mandatory invitation`() {
        assertEquals("first", TelegramReminderPolicy.stage(false, false, "", "launch-a"))
    }
    @Test fun `second invitation waits for a later launch`() {
        assertEquals("none", TelegramReminderPolicy.stage(true, false, "launch-a", "launch-a"))
        assertEquals("second", TelegramReminderPolicy.stage(true, false, "launch-a", "launch-b"))
    }
    @Test fun `existing joined installations get one optional reminder`() {
        assertEquals("second", TelegramReminderPolicy.stage(true, false, "", "launch-a"))
    }
    @Test fun `completed followup is never offered again`() {
        assertEquals("none", TelegramReminderPolicy.stage(true, true, "launch-a", "launch-b"))
        assertEquals("none", TelegramReminderPolicy.stage(true, true, "", "launch-c"))
    }
}
