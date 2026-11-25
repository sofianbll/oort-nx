package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfBuild
import io.github.sofianbll.oortnx.shelf.ShelfCatalog
import io.github.sofianbll.oortnx.shelf.ShelfConnector
import io.github.sofianbll.oortnx.shelf.ShelfConnectors
import io.github.sofianbll.oortnx.shelf.ShelfCrypto
import io.github.sofianbll.oortnx.shelf.ShelfDevice
import io.github.sofianbll.oortnx.shelf.ShelfDownload
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfListing
import io.github.sofianbll.oortnx.shelf.ShelfOrder
import io.github.sofianbll.oortnx.shelf.ShelfPlatform
import io.github.sofianbll.oortnx.shelf.ShelfRetry
import io.github.sofianbll.oortnx.shelf.ShelfRules
import io.github.sofianbll.oortnx.shelf.ShelfStop
import io.github.sofianbll.oortnx.shelf.ShelfStore
import io.github.sofianbll.oortnx.shelf.hex
import io.github.sofianbll.oortnx.shelf.jsonObject
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.nio.file.Files
import java.util.Base64
import java.util.concurrent.CancellationException
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** The cases of Tests/PhoneLibrary/vectors, which the iPhone package answers too. */
@RunWith(Parameterized::class)
class VectorTest(private val name: String) {
    @Suppress("UNCHECKED_CAST")
    @Test
    fun vector() {
        val file = File(FakeDrive.folder, "vectors/$name.json")
        val vector = Json.read(file.readBytes()).jsonObject()!!
        val client = vector["client"].jsonObject()!!
        val device = client["device"].jsonObject()!!
        val work = Files.createTempDirectory("oort-drive").toFile()
        FakeDrive(file).use { drive ->
            val scratch = File(work, "scratch")
            val waits = mutableListOf<Int>()
            val vault = MemoryVault(DriveSecret("RT-CANARY-0"))
            val key = Base64.getDecoder().decode(vector["key"] as String)
            val crypto = ShelfCrypto(key)
            val root = vector["drive"].jsonObject()!!["root"] as String
            val invite = DriveInvite(DriveClient("1-a.apps.googleusercontent.com", DriveClient.Kind.IOS, null), root, key)
            val connection = DriveConnection(invite, vault, DriveHttp, drive.endpoints(client["network"] == "up"), scratch)
            val connectors = ShelfConnectors(listOf(connection.connector), MemoryChoices())
            if (client["on"] == true) connectors.turnOn(DriveConnection.ID, ShelfConnector.Permission.entries.toSet())
            val retry = ShelfRetry { seconds, _ -> waits.add(seconds) }
            val store = ShelfStore(File(work, "store")) { client["free"] as Long }
            val here = ShelfDevice(
                ShelfPlatform.entries.first { it.id == device["platform"] }, device["system"] as String, device["architecture"] as String,
                (device["features"] as List<String>).toSet(), (device["host"] as Long).toInt(),
            )
            val rules = ShelfRules(client["allow_metered"] as Boolean, client["chunk"] as Long, client["reserve"] as Long)
            fun catalog() = ShelfCatalog(connectors.source(DriveConnection.ID), crypto, scratch, retry)
            fun list(installed: Map<String, String> = emptyMap(), order: ShelfOrder = ShelfOrder.NAME): ShelfListing = catalog().list(here, installed, order)
            // The builds are known from an unhurried listing; a fault may be meant for the download alone.
            val known = HashMap<String, ShelfBuild>()

            for ((number, item) in (vector["steps"] as List<*>).withIndex()) {
                val step = item.jsonObject()!!
                val expected = step["expect"].jsonObject()!!
                val label = "$name, step $number"
                val title = step["title"] as? String
                if (title != null && title !in known && step["do"] in listOf("download", "discard", "tamper_part")) {
                    list().games.forEach { known[it.titleID] = it.build }
                    assertNotNull(known[title], label)
                }
                drive.log()
                waits.clear()
                var code: String? = null
                try {
                    when (step["do"]) {
                        "list" -> {
                            val installed = if (step["installed"] == "store") store.installed() else step["installed"] as? Map<String, String> ?: emptyMap()
                            val listing = list(installed, ShelfOrder.entries.first { it.id == (step["order"] ?: "name") })
                            expected["games"]?.let { games ->
                                assertEquals(games, listing.games.map { mapOf("title" to it.titleID, "name" to it.name, "version" to it.build.gameVersion, "digest" to it.build.digest, "state" to it.state.id) }, label)
                            }
                            expected["hidden"]?.let { assertEquals(it, listing.hidden.map { h -> listOf(h.titleID, h.name, h.reason.id) }, label) }
                            expected["problems"]?.let { assertEquals(it, listing.problems.map { p -> listOf(p.titleID, p.error.code) }, label) }
                        }
                        "mac" -> {
                            val build = assertNotNull(catalog().macBuild(title!!), label)
                            if (expected["version"] != null) {
                                assertEquals(listOf(expected["name"], expected["version"], expected["engine"], expected["bytes"], expected["stamp"]), listOf(build.name, build.gameVersion, build.engineCommit, build.bytes, build.stamp), label)
                            }
                        }
                        "download" -> {
                            val build = known.getValue(title!!)
                            val halt = step["cancel_after"] as? Long
                            var chunks = -1L
                            val stop = ShelfStop()
                            val download = ShelfDownload(connectors.source(DriveConnection.ID), store, rules, retry) { client["metered"] as Boolean }
                            val visible = download.run(build, stop) {
                                assertTrue(it.received <= it.total && it.total == build.bytes, label)
                                chunks++
                                if (chunks == halt) stop.stop()
                            }
                            val wanted = assertNotNull(expected["files"], label)
                            assertEquals(wanted, visible.walk().filter { it.isFile }.associate { it.relativeTo(visible).path to ShelfCrypto.sha256().digest(it.readBytes()).hex() } as Any, label)
                        }
                        "discard" -> store.discard(known.getValue(title!!))
                        "turn_off" -> connectors.turnOff(DriveConnection.ID)
                        "credential" -> Unit
                        "tamper_part" -> {
                            val part = work.walk().first { it.extension == "part" }
                            part.writeBytes(part.readBytes().also { it[0] = (it[0].toInt() xor 0xFF).toByte() })
                        }
                        else -> throw AssertionError(label)
                    }
                } catch (_: CancellationException) {
                    code = "cancelled"
                } catch (failure: ShelfException) {
                    code = failure.error.code
                    val trace = StringWriter().also { failure.printStackTrace(PrintWriter(it)) }.toString()
                    assertFalse("CANARY" in trace || "127.0.0.1" in trace, label)
                }
                assertEquals(expected["error"], code, label)
                val calls = drive.log()
                assertFalse(calls.any { it.call in listOf("write", "other", "revoke") }, label)
                step["calls"]?.let { assertEquals(it, calls.count { c -> c.call != "token" }.toLong(), label) }
                step["waits"]?.let { assertEquals(it, waits.map { s -> s.toLong() }, label) }
                (step["media"] as? List<List<Any?>>)?.let { media ->
                    assertEquals(media.map { "${it[0]} ${it[1]}-${it[2]}" }, calls.filter { it.call == "media" }.map { "${it.node} ${it.first}-${it.last}" }, label)
                }
                expected["credential"]?.let { assertEquals(it, vault.read() != null, label) }
                known[title]?.let { build ->
                    expected["visible"]?.let { assertEquals(it, store.visible(build).exists(), label) }
                    expected["waiting"]?.let { assertEquals(it, store.waiting(build).exists(), label) }
                }
                work.walk().filter { it.isFile }.forEach { assertFalse("CANARY" in it.readText(Charsets.ISO_8859_1), label) }
            }
            assertTrue(scratch.walk().none { it.isFile }, "nothing is left behind")
        }
        work.deleteRecursively()
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun names(): List<Array<String>> = File(FakeDrive.folder, "vectors").list()!!.filter { it.endsWith(".json") }.sorted().map { arrayOf(it.removeSuffix(".json")) }
            .also { check(it.size >= 75) }
    }
}
