package dev.nirang.client.subscription

import java.io.File
import java.io.IOException
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class LocalAetherProfileStoreTest {
    @get:Rule val temporary=TemporaryFolder()
    @Test fun `older local catalogue gets one Irancell preset without rewriting existing profiles`() {
        val file=File(temporary.newFolder(),"profiles")
        val original=AetherProfiles.defaults().take(2)
        file.writeText(org.json.JSONObject().put("version",1).put("profiles",org.json.JSONArray(original.map(CustomProfile::toPrivateJson))).toString())
        val store=LocalAetherProfileStore(file,{it.readText()},{f,t->f.writeText(t)})
        assertEquals(original,store.load().take(2))
        assertEquals(3,store.load().size)
        store.save(original.first().id,"renamed",original.first().payload)
        assertEquals(1,store.load().count { it.id == "builtin_wireguard_irancell" })
    }
    @Test fun `a saved profile survives a new store and retains both defaults`() {
        val file=File(temporary.newFolder(),"profiles")
        fun store()=LocalAetherProfileStore(file,{it.readText()},{f,t->f.writeText(t)})
        val created=store().save(null,"personal","{\"mode\":\"masque\"}")
        assertEquals(4,store().load().size)
        assertEquals(created,store().load().last())
        assertEquals(created.id,store().save(created.id,"renamed",created.payload).id)
    }
    @Test fun `failed validation and failed writes retain previous stored data`() {
        val file=File(temporary.newFolder(),"profiles")
        val store=LocalAetherProfileStore(file,{it.readText()},{f,t->f.writeText(t)})
        store.save(null,"personal","{\"mode\":\"masque\"}")
        val before=file.readText()
        try { store.save(null,"bad","{\"mode\":\"masque\",\"privateKey\":\"leak\"}");fail() } catch (_:IllegalArgumentException) { }
        assertEquals(before,file.readText())
        try { LocalAetherProfileStore(file,{it.readText()},{_,_->throw IOException()}).save(null,"new","{\"mode\":\"masque\"}");fail() } catch (_:IOException) { }
        assertEquals(before,file.readText())
    }
}
