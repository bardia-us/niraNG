package dev.nirang.client.vpn

import android.content.Context
import dev.nirang.client.model.ConnectionState
import dev.nirang.client.subscription.SubscriptionRepository
import dev.nirang.client.subscription.Target
import dev.nirang.client.subscription.Profile
import dev.nirang.client.cores.aether.AetherSession
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Before
import org.junit.After
import org.junit.Test

/** Compiles the actual restart coordinator; doubles replace only Android/native/storage I/O. */
class VpnRestartCoordinatorHostTest {
    private val context = Context()
    @Before fun reset() {
        VpnRestartCoordinator.cancel()
        Thread.sleep(150)
        SubscriptionRepository.servers.clear()
        SubscriptionRepository.servers["old"] = Target("old","old")
        SubscriptionRepository.servers["edited"] = Target("edited","edited",Profile("aether","""{"psiphon":"only","startupTimeoutSeconds":30}"""))
        SubscriptionRepository.servers["newest"] = Target("newest","newest")
        SubscriptionRepository.onSelect = null
        NirangVpnService.activeId = "old"
        NirangVpnService.starts.clear();NirangVpnService.stops.clear();NirangVpnService.stopHook = null
        AetherSession.prepareHook = null;AetherSession.stopHook = null
        ConnectionPreflight.rejected = null;ConnectionPreflight.validated.clear()
        ConnectionStore.transition(ConnectionState.CONNECTED,"queued_selection","queued")
    }
    @After fun cancel() {
        SubscriptionRepository.onSelect = null
        VpnRestartCoordinator.cancel()
        Thread.sleep(150)
    }
    @Test fun `disconnect during final selection cannot revive stopped VPN`() {
        val selected = CountDownLatch(1)
        SubscriptionRepository.onSelect = {
            VpnRestartCoordinator.cancel()
            ConnectionStore.transition(ConnectionState.DISCONNECTED)
            selected.countDown()
        }
        assertTrue(VpnRestartCoordinator.request(context,"edited"))
        assertTrue(selected.await(3,TimeUnit.SECONDS))
        Thread.sleep(100)
        assertEquals(emptyList<String>(),NirangVpnService.starts.toList())
        assertEquals(ConnectionState.DISCONNECTED,ConnectionStore.state())
    }
    @Test fun `replacement arriving during selection starts only newest target`() {
        val selected = CountDownLatch(1)
        SubscriptionRepository.onSelect = { id ->
            if (id == "edited") {
                SubscriptionRepository.onSelect = null
                assertTrue(VpnRestartCoordinator.request(context,"newest"))
                selected.countDown()
            }
        }
        assertTrue(VpnRestartCoordinator.request(context,"edited"))
        assertTrue(selected.await(3,TimeUnit.SECONDS))
        await { NirangVpnService.starts.contains("newest") }
        assertEquals(listOf("newest"),NirangVpnService.starts.toList())
        assertTrue(ConnectionPreflight.validated.contains("newest"))
    }
    @Test fun `invalid profile retains real service identity instead of queued UI selection`() {
        ConnectionPreflight.rejected = "edited"
        assertTrue(VpnRestartCoordinator.request(context,"edited"))
        await { ConnectionStore.state() == ConnectionState.CONNECTED }
        assertEquals("old",ConnectionStore.snapshot()["serverId"])
        assertEquals("old",SubscriptionRepository.selected)
        assertTrue(NirangVpnService.stops.isEmpty())
        assertTrue(NirangVpnService.starts.isEmpty())
    }
    @Test fun `stop while awaiting service teardown cancels restart promptly`() {
        val stopping = CountDownLatch(1)
        NirangVpnService.stopHook = { stopping.countDown() }
        assertTrue(VpnRestartCoordinator.request(context,"edited"))
        assertTrue(stopping.await(3,TimeUnit.SECONDS))
        VpnRestartCoordinator.cancel()
        ConnectionStore.transition(ConnectionState.DISCONNECTED)
        Thread.sleep(150)
        assertTrue(NirangVpnService.starts.isEmpty())
        assertEquals(ConnectionState.DISCONNECTED,ConnectionStore.state())
    }
    @Test fun `stop while native preparation blocks stops preparation and never starts VPN`() {
        val preparing = CountDownLatch(1);val released = CountDownLatch(1)
        AetherSession.prepareHook = { preparing.countDown();assertTrue(released.await(3,TimeUnit.SECONDS)) }
        AetherSession.stopHook = { released.countDown() }
        assertTrue(VpnRestartCoordinator.request(context,"edited"))
        assertTrue(preparing.await(3,TimeUnit.SECONDS))
        VpnRestartCoordinator.cancel()
        assertTrue(released.await(1,TimeUnit.SECONDS))
        Thread.sleep(150)
        assertTrue(NirangVpnService.starts.isEmpty())
        assertTrue(NirangVpnService.stops.isEmpty())
    }
    private fun await(predicate: ()->Boolean) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(4)
        while (!predicate() && System.nanoTime() < deadline) Thread.sleep(10)
        assertTrue("Coordinator did not complete",predicate())
    }
}
