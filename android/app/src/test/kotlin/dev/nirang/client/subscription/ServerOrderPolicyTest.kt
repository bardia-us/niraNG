package dev.nirang.client.subscription

import dev.nirang.client.model.ServerRecord
import org.junit.Assert.assertEquals
import org.junit.Test

class ServerOrderPolicyTest {
    @Test
    fun `stored order survives refresh and new servers append in subscription order`() {
        val result = ServerOrderPolicy.apply(listOf("b", "a", "removed"), listOf(server("a"), server("c"), server("b")))
        assertEquals(listOf("b", "a", "c"), result.map(ServerRecord::id))
    }

    @Test
    fun `move follows Flutter reorder index semantics`() {
        assertEquals(listOf("b", "c", "a"), ServerOrderPolicy.move(listOf("a", "b", "c"), 0, 3))
        assertEquals(listOf("c", "a", "b"), ServerOrderPolicy.move(listOf("a", "b", "c"), 2, 0))
    }

    @Test
    fun `legacy identifiers and endpoint changes keep a matching custom order`() {
        val oldA = server("legacy-a")
        val oldB = server("legacy-b").copy(address = "b.example.com")
        val newA = oldA.copy(id = "semantic-a", name = "Renamed")
        val newB = oldB.copy(id = "semantic-b")

        val result = ServerOrderPolicy.afterRefresh(
            listOf("legacy-b", "legacy-a"),
            listOf(oldA, oldB),
            listOf(newA, newB),
        )
        assertEquals(listOf("semantic-b", "semantic-a"), result.map(ServerRecord::id))
    }

    @Test
    fun `changed Shadowsocks and first subscription server never fall to the end`() {
        val first = server("first")
        val middle = server("middle").copy(address = "middle.example.com")
        val ss = server("ss-old").copy(protocol = "shadowsocks", address = "ss.example.com", credential = "old")
        val last = server("last").copy(address = "last.example.com")
        val refreshedFirst = first.copy(id = "first-new", parameters = mapOf("path" to "/changed"))
        val refreshedSs = ss.copy(id = "ss-new", credential = "new")

        val result = ServerOrderPolicy.afterRefresh(
            listOf("first", "middle", "ss-old", "last"),
            listOf(first, middle, ss, last),
            listOf(refreshedFirst, middle, refreshedSs, last),
        )

        assertEquals(listOf("first-new", "middle", "ss-new", "last"), result.map(ServerRecord::id))
    }

    @Test
    fun `manual order survives while a new source neighbour is inserted logically`() {
        val a = server("a")
        val b = server("b").copy(address = "b.example.com")
        val c = server("c").copy(address = "c.example.com")
        val fresh = server("new").copy(address = "new.example.com")

        val result = ServerOrderPolicy.afterRefresh(
            listOf("c", "a", "b"),
            listOf(a, b, c),
            listOf(a, fresh, b, c),
        )

        assertEquals(listOf("c", "a", "new", "b"), result.map(ServerRecord::id))
    }

    private fun server(id: String) = ServerRecord(id, id, "", "vless", "example.com", 443, "uuid", "tcp", "tls", emptyMap())
}
