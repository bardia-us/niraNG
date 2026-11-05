package dev.nirang.client.cores.aether

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import java.security.KeyFactory
import java.security.Signature
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.PKCS8EncodedKeySpec

/** Each identity is independent. Failed first-connect provisioning never replaces retained keys. */
internal class AetherIdentityStore(private val directory: File) {
    fun copyRetained(options: AetherOptions, destination: File) = withIdentityLock({
        if (Thread.currentThread().isInterrupted) throw InterruptedException("Probe cancelled")
    }) {
        val pending=pendingReplacement()
        require(destination.canonicalFile != directory.canonicalFile) { "Probe identity must be isolated" }
        check(destination.isDirectory || destination.mkdirs()) { "Probe storage is unavailable" }
        options.identityFiles.forEach { name ->
            // Probing may read the last complete generation but never repairs or
            // replaces authoritative keys. Connection/explicit preparation recovers.
            val state=pending?.second?.get(name)
            val source=if(state == "present") File(pending.first,"before/$name") else File(directory,name)
            if(state == "absent") return@forEach
            if(source.isFile) {
                check(source.length() in 1..65536) { "Retained identity is invalid" }
                source.copyTo(File(destination,name),overwrite=false)
            }
        }
    }
    fun ensure(options: AetherOptions, checkCancelled: () -> Unit, forceRenew: Boolean = false, provision: (File) -> Unit) = withIdentityLock(checkCancelled) {
        checkCancelled()
        recoverInterruptedReplacement()
        if (!forceRenew && options.identityFiles.all { ready(File(directory, it), it.contains("masque") && !it.contains("gool")) }) return@withIdentityLock
        check(directory.isDirectory || directory.mkdirs()) { "Private Aether identity storage is unavailable" }
        val staging = File(directory, ".provision-${UUID.randomUUID()}")
        check(staging.mkdir()) { "Could not stage secure registration" }
        staging.setReadable(false, false); staging.setWritable(false, false); staging.setExecutable(false, false)
        staging.setReadable(true, true); staging.setWritable(true, true); staging.setExecutable(true, true)
        var retainRecovery = false
        try {
            if (!forceRenew) options.identityFiles.forEach { name ->
                val original = File(directory, name)
                if (original.isFile) original.copyTo(File(staging, name))
            }
            provision(staging)
            checkCancelled()
            check(options.identityFiles.all { File(staging, it).isFile }) { "Registration did not return every required identity" }
            check(options.identityFiles.all { ready(File(staging,it),it.contains("masque") && !it.contains("gool")) }) {
                "Registration did not return a valid identity"
            }
            checkCancelled()
            // Persist the old tuple before promoting any file. A process death between the
            // MASQUE/Gool moves is recovered on the next use, including a probe snapshot.
            val before=File(staging,"before").apply { check(mkdir()) }
            val records=options.identityFiles.map { name ->
                val original=File(directory,name)
                if(original.isFile) {
                    check(original.length() in 1..65536) { "Retained identity is invalid" }
                    durableWrite(File(before,name),original.readBytes())
                    "$name:present"
                } else "$name:absent"
            }
            val next=File(directory,".identity-transaction.new")
            durableWrite(next,(staging.name+"\n"+records.joinToString("\n")+"\n").toByteArray())
            atomicReplace(next,File(directory,".identity-transaction"))
            options.identityFiles.forEach { name ->
                checkCancelled()
                atomicReplace(File(staging,name),File(directory,name))
            }
            Files.delete(File(directory,".identity-transaction").toPath())
        } catch (failure: Throwable) {
            runCatching { recoverInterruptedReplacement() }.onFailure { retainRecovery=true }
            throw failure
        } finally { if(!retainRecovery) staging.deleteRecursively() }
    }

    private fun pendingReplacement():Pair<File,Map<String,String>>? {
        val journal=File(directory,".identity-transaction")
        if(!journal.exists()) return null
        check(journal.isFile && journal.length() in 1..1024) { "Identity recovery is unavailable" }
        val lines=journal.readLines()
        check(lines.first().matches(Regex("\\.provision-[0-9a-fA-F-]{36}"))) { "Invalid identity recovery" }
        val staging=File(directory,lines.first())
        check(staging.canonicalFile.parentFile == directory.canonicalFile && staging.isDirectory) { "Invalid identity recovery path" }
        check(lines.size in 2..4) { "Invalid identity recovery entries" }
        val entries=linkedMapOf<String,String>()
        lines.drop(1).forEach { entry ->
            val parts=entry.split(':')
            check(parts.size == 2 && parts[0] in IDENTITY_NAMES && parts[1] in setOf("present","absent")) { "Invalid identity recovery entry" }
            check(entries.put(parts[0],parts[1]) == null) { "Duplicate recovery identity" }
        }
        return staging to entries
    }

    private fun recoverInterruptedReplacement() {
        val (staging,entries)=pendingReplacement() ?: return
        entries.forEach { (name,state) ->
            if(state == "absent") Files.deleteIfExists(File(directory,name).toPath())
            else {
                val backup=File(staging,"before/$name")
                check(backup.isFile && backup.length() in 1..65536) { "Identity recovery copy is unavailable" }
                val restore=File(staging,"restore-$name")
                durableWrite(restore,backup.readBytes())
                atomicReplace(restore,File(directory,name))
            }
        }
        Files.delete(File(directory,".identity-transaction").toPath())
        staging.deleteRecursively()
    }

    private fun durableWrite(file:File,bytes:ByteArray) {
        java.io.FileOutputStream(file).use { it.write(bytes); it.fd.sync() }
    }

    private fun atomicReplace(source:File,target:File) {
        Files.move(source.toPath(),target.toPath(),StandardCopyOption.REPLACE_EXISTING,StandardCopyOption.ATOMIC_MOVE)
    }

    private fun <T> withIdentityLock(checkCancelled:()->Unit,action:()->T):T {
        while(true) {
            checkCancelled()
            if(lock.tryLock(100,TimeUnit.MILLISECONDS)) break
        }
        try { checkCancelled(); return action() } finally { lock.unlock() }
    }

    private fun ready(file: File, masque: Boolean): Boolean = runCatching {
        if (!file.isFile || file.length() !in 1..65536) return false
        val text = file.readText()
        fun field(name: String): String? = Regex("(?m)^${Regex.escape(name)}\\s*=\\s*\"([^\"]+)\"\\s*$").find(text)?.groupValues?.get(1)
        if (field("device_id") == null || field("access_token") == null) return false
        for (name in listOf("wg_private_key", "wg_peer_public_key")) {
            if (Base64.getDecoder().decode(field(name) ?: return false).size != 32) return false
        }
        if (masque) {
            val issued = Regex("(?m)^cert_issued_at\\s*=\\s*([0-9]+)\\s*$").find(text)?.groupValues?.get(1)?.toLongOrNull() ?: return false
            val age = System.currentTimeMillis() / 1000 - issued
            if (age !in 0 until 358L * 86400) return false
            fun pem(name:String):String? {
                val multiline=Regex("(?ms)^${Regex.escape(name)}\\s*=\\s*(?:\"\"\"\\r?\\n?(.*?)\"\"\"|'''\\r?\\n?(.*?)''')").find(text)
                return if(multiline != null) multiline.groupValues.drop(1).firstOrNull { it.isNotEmpty() }
                    else field(name)?.replace("\\n","\n")?.replace("\\r","\r")
            }
            val cert=CertificateFactory.getInstance("X.509").generateCertificate((pem("cert_pem") ?: return false).byteInputStream()) as X509Certificate
            cert.checkValidity()
            val keyText=pem("key_pem") ?: return false
            val encoded=Regex("-----BEGIN PRIVATE KEY-----\\s*([A-Za-z0-9+/=\\s]+)-----END PRIVATE KEY-----").find(keyText)?.groupValues?.get(1) ?: return false
            val key=KeyFactory.getInstance(cert.publicKey.algorithm).generatePrivate(PKCS8EncodedKeySpec(Base64.getMimeDecoder().decode(encoded)))
            val algorithm=when(cert.publicKey.algorithm) { "EC" -> "SHA256withECDSA"; "RSA" -> "SHA256withRSA"; else -> return false }
            val challenge="niraNG identity validation".toByteArray()
            val signature=Signature.getInstance(algorithm)
            signature.initSign(key); signature.update(challenge)
            val proof=signature.sign()
            signature.initVerify(cert.publicKey); signature.update(challenge)
            if(!signature.verify(proof)) return false
        }
        true
    }.getOrDefault(false)

    companion object {
        private val lock = ReentrantLock()
        private val IDENTITY_NAMES=setOf("aether-wg.toml","aether-masque.toml","aether-masque-gool.toml","aether-wg-secondary.toml","aether-masque-secondary.toml")
    }
}
