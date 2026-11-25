package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.ShelfConnector
import io.github.sofianbll.oortnx.shelf.ShelfConnectors
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfNode
import io.github.sofianbll.oortnx.shelf.ShelfSource
import io.github.sofianbll.oortnx.shelf.ShelfStop
import org.junit.After
import org.junit.Test
import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Socket
import java.net.URI
import java.nio.file.Files
import java.security.KeyPairGenerator
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.KeyGenerator
import kotlin.concurrent.thread
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DriveAccessTest {
    private val signer = publicKey("secp256r1")
    private val client = "1234-abc.apps.googleusercontent.com"
    private val work: File = Files.createTempDirectory("oort-drive").toFile()
    private val listIOS = File(FakeDrive.folder, "vectors/list-ios.json")

    @After fun clean() { work.deleteRecursively() }

    private fun publicKey(curve: String): String =
        Base64.getEncoder().encodeToString(KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec(curve)) }.generateKeyPair().public.encoded)

    private fun code(vararg changes: Pair<String, String?>): String {
        val map = linkedMapOf<String, String?>("oort" to "drive-1", "kind" to "ios", "client" to client, "folder" to "1AbC_d-E", "signer" to signer)
        changes.forEach { (key, value) -> if (value == null) map.remove(key) else map[key] = value }
        return map.entries.joinToString(",", "{", "}") { "\"${it.key}\":\"${it.value!!.replace("\n", "\\n")}\"" }
    }

    private fun refuses(error: ShelfError, body: () -> Unit) = assertEquals(error, assertFailsWith<ShelfException> { body() }.error)

    @Test fun `the code to scan is strict`() {
        assertEquals("1AbC_d-E", assertNotNull(DriveInvite.parse(code())).folder)
        val desktop = assertNotNull(DriveInvite.parse(code("kind" to "desktop", "secret" to "GOCSPX-s3cret_value")))
        assertFalse("s3cret" in desktop.client.toString())
        val refused = listOf(
            listOf("refresh_token" to "x"), listOf("access_token" to "x"), listOf("token" to "x"), listOf("extra" to ""), listOf("oort" to "drive-2"), listOf("kind" to "web"),
            listOf("client" to "evil.example.com"), listOf("client" to "a.apps.googleusercontent.com.evil"), listOf("client" to client + "\n"), listOf("folder" to "root"),
            listOf("folder" to "a'b"), listOf("folder" to "-x"), listOf("folder" to ""), listOf("signer" to "AAAA"), listOf("signer" to publicKey("secp384r1")),
            listOf("signer" to null), listOf("client" to null), listOf("secret" to "with-ios"), listOf("kind" to "desktop", "secret" to "a&b=c"),
            listOf("folder" to "a".repeat(2000)),
        )
        refused.forEach { assertNull(DriveInvite.parse(code(*it.toTypedArray())), it.toString()) }
        listOf("", "https://example.com", "[]", "{\"oort\":1}", "drive-1", code() + code()).forEach { assertNull(DriveInvite.parse(it)) }
    }

    @Test fun `the sign-in page asks to read and nothing else`() {
        DriveReceiver().use { receiver ->
            val signIn = DriveSignIn(DriveInvite.parse(code())!!.client, receiver)
            val page = URI(signIn.page)
            val items = page.query.split("&").associate { it.substringBefore("=") to it.substringAfter("=") }
            assertEquals("https://accounts.google.com/o/oauth2/v2/auth", signIn.page.substringBefore("?"))
            assertEquals("https://www.googleapis.com/auth/drive.readonly", items["scope"])
            assertEquals("S256", items["code_challenge_method"])
            assertEquals(receiver.address, items["redirect_uri"])
            assertEquals(listOf("client_id", "code_challenge", "code_challenge_method", "redirect_uri", "response_type", "scope", "state"), items.keys.sorted())
            assertFalse(signIn.verifier.reveal() in signIn.page)
            val other = DriveSignIn(signIn.client, receiver)
            assertNotEquals(other.verifier, signIn.verifier)
            assertNotEquals(other.state, signIn.state)
            assertEquals(64, signIn.verifier.reveal().length)
        }
        // RFC 7636, appendix B.
        assertEquals("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", DriveSignIn.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
    }

    @Test fun `google only`() = assertEquals(listOf("accounts.google.com", "oauth2.googleapis.com", "www.googleapis.com"), DriveEndpoints.google.hosts)

    private fun connection(drive: FakeDrive, vault: DriveVault, scratch: File = File(work, "scratch")) =
        DriveConnection(DriveInvite.parse(code("folder" to "ROOT"))!!, vault, DriveHttp, drive.endpoints(), scratch)

    private fun signIn(drive: FakeDrive, redirect: String = "http://127.0.0.1:4000") =
        DriveSignIn(DriveInvite.parse(code())!!.client, DriveSecret(DriveSignIn.random()), DriveSecret(DriveSignIn.random()), redirect, drive.endpoints())

    private fun get(url: String): Int = (URI(url).toURL().openConnection() as java.net.HttpURLConnection).run { responseCode.also { disconnect() } }

    @Test fun `signing in through the browser keeps the refresh token in the vault only`() = FakeDrive(listIOS).use { drive ->
        val vault = MemoryVault(null)
        val connection = connection(drive, vault)
        DriveReceiver().use { receiver ->
            val signIn = signIn(drive, receiver.address)
            drive.remember("CODE-1", DriveSignIn.challenge(signIn.verifier.reveal()))
            val answers = mutableListOf<Int>()
            val browser = thread {
                // What else a phone may throw at the port, then Google's answer.
                answers += get("${receiver.address}/favicon.ico")
                answers += get("${receiver.address}/?state=guess&code=EVIL")
                answers += get("${receiver.address}/elsewhere?state=${signIn.state.reveal()}&code=EVIL")
                Socket("127.0.0.1", URI(receiver.address).port).use { it.getOutputStream().write("POST / HTTP/1.1\r\n\r\n".toByteArray()) }
                answers += get("${receiver.address}/?state=${signIn.state.reveal()}&code=CODE-1&scope=x")
            }
            val callback = receiver.receive(signIn, ShelfStop(), 20)
            browser.join()
            assertEquals(listOf(404, 404, 404, 200), answers)
            connection.access.finish(signIn, callback)
        }
        assertEquals("RT-CANARY-NEW", vault.read()!!.reveal())
        val connectors = ShelfConnectors(listOf(connection.connector), MemoryChoices())
        connectors.turnOn(DriveConnection.ID, ShelfConnector.Permission.entries.toSet())
        val source = connectors.source(DriveConnection.ID)
        assertTrue(source.children("ROOT", ShelfStop()).isNotEmpty())
        assertEquals(listOf("client_id", "code", "code_verifier", "grant_type", "redirect_uri"), drive.log().first { it.call == "token" }.fields)
        assertFalse("CANARY" in vault.read().toString())
        connection.access.forget()
        assertNull(vault.read())
        refuses(ShelfError.SignInNeeded) { source.children("ROOT", ShelfStop()) }
        assertFalse(drive.log().any { it.call == "revoke" })
    }

    @Test fun `the receiver listens on the device only, and can be stopped`() {
        val receiver = DriveReceiver()
        val port = URI(receiver.address).port
        assertTrue(NetworkInterface.getNetworkInterfaces().toList().flatMap { it.inetAddresses.toList() }.filter { !it.isLoopbackAddress && it is java.net.Inet4Address }.none { address ->
            try { Socket().use { it.connect(InetSocketAddress(address, port), 500) }; true } catch (_: java.io.IOException) { false }
        })
        assertEquals("127.0.0.1", InetAddress.getByName(URI(receiver.address).host).hostAddress)
        val stop = ShelfStop()
        thread { Thread.sleep(200); stop.stop() }
        FakeDrive(listIOS).use { drive -> assertFailsWith<CancellationException> { receiver.receive(signIn(drive, receiver.address), stop, 20) } }
        DriveReceiver().use { late -> FakeDrive(listIOS).use { drive -> refuses(ShelfError.Interrupted) { late.receive(signIn(drive, late.address), ShelfStop(), 1) } } }
    }

    @Test fun `a stolen or foreign answer is refused`() = FakeDrive(listIOS).use { drive ->
        val vault = MemoryVault(null)
        val connection = connection(drive, vault)
        val signIn = signIn(drive)
        val state = signIn.state.reveal()
        val back = signIn.redirect
        listOf(
            "$back?code=C" to ShelfError.BadResponse, "$back?state=other&code=C" to ShelfError.BadResponse, "$back?state=$state" to ShelfError.BadResponse,
            "$back?state=$state&code=C&code=D" to ShelfError.BadResponse, "$back?state=$state&state=$state&code=C" to ShelfError.BadResponse,
            "other.app:/oauth2redirect?state=$state&code=C" to ShelfError.BadResponse, "$back/elsewhere?state=$state&code=C" to ShelfError.BadResponse,
            "http://127.0.0.1:4001?state=$state&code=C" to ShelfError.BadResponse, "http://evil.example:4000?state=$state&code=C" to ShelfError.BadResponse,
            "$back?state=$state&error=access_denied" to ShelfError.AccessDenied, "$back?error=access_denied" to ShelfError.BadResponse, "%%" to ShelfError.BadResponse,
        ).forEach { (text, error) -> refuses(error) { connection.access.finish(signIn, text) } }
        assertTrue(drive.log().isEmpty())
        // A code taken by another app is worth nothing without the verifier.
        drive.remember("CODE-2", DriveSignIn.challenge("another verifier"))
        refuses(ShelfError.SignInNeeded) { connection.access.finish(signIn, "$back?state=$state&code=CODE-2") }
        assertNull(vault.read())
    }

    @Test fun `another scope is refused`() {
        for (scope in listOf("https://www.googleapis.com/auth/drive", DriveSignIn.SCOPE + " https://www.googleapis.com/auth/drive", "openid", "")) {
            val vector = File(work, "vector.json")
            vector.writeText(listIOS.readText().replace("\"faults\": []", "\"faults\": [{\"on\": \"token\", \"times\": 9, \"do\": \"shrink\", \"scope\": \"$scope\"}]").also { check("shrink" in it) })
            FakeDrive(vector).use { drive ->
                val vault = MemoryVault(null)
                val signIn = signIn(drive)
                drive.remember("CODE", DriveSignIn.challenge(signIn.verifier.reveal()))
                refuses(ShelfError.AccessDenied) { connection(drive, vault).access.finish(signIn, "${signIn.redirect}?state=${signIn.state.reveal()}&code=CODE") }
                assertNull(vault.read())
            }
        }
    }

    @Test fun `requests refused together renew once`() = FakeDrive(listIOS).use { drive ->
        val access = connection(drive, MemoryVault(DriveSecret("RT-CANARY-0"))).access
        val pool = Executors.newFixedThreadPool(8)
        val tokens = (0 until 8).map { pool.submit<DriveSecret> { access.token(null, ShelfStop()) } }.map { it.get(20, TimeUnit.SECONDS).reveal() }.toSet()
        pool.shutdown()
        assertEquals(1, tokens.size)
        assertEquals(1, drive.log().count { it.call == "token" })
    }

    /** With a key of this JVM: the device's keystore does not exist here. */
    @Test fun `the sealed vault holds nothing readable`() {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        val file = File(work, "vault/token")
        var erased = 0
        val vault = DriveSealedVault(file, { key }) { erased++ }
        assertNull(vault.read())
        vault.write(DriveSecret("RT-CANARY-1"))
        val first = file.readBytes()
        vault.write(DriveSecret("RT-CANARY-1"))
        assertFalse(first.contentEquals(file.readBytes()), "a fresh nonce each time")
        assertFalse("CANARY" in file.readText(Charsets.ISO_8859_1))
        assertEquals("RT-CANARY-1", vault.read()!!.reveal())
        val other = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        assertNull(DriveSealedVault(file, { other }).read(), "another device's key")
        file.writeBytes(file.readBytes().also { it[20] = (it[20].toInt() xor 1).toByte() })
        assertNull(vault.read(), "a changed file")
        file.writeBytes(ByteArray(3))
        assertNull(vault.read())
        vault.erase()
        assertFalse(file.exists())
        assertEquals(1, erased)
        assertEquals(listOf<String>(), file.parentFile!!.list()!!.toList())
    }

    @Test fun `a connector is off until the player agrees to everything it asks`() {
        val choices = MemoryChoices()
        var opened = 0
        var forgotten = 0
        val empty = object : ShelfSource {
            override val root = "R"
            override fun children(folder: String, stop: ShelfStop) = emptyList<ShelfNode>()
            override fun fetch(file: ShelfNode, first: Long, count: Long, destination: File, stop: ShelfStop) = Unit
        }
        fun connector(permissions: Set<ShelfConnector.Permission>) = ShelfConnector("x", emptyList(), permissions, { opened++; empty }, { forgotten++ })
        val some = setOf(ShelfConnector.Permission.NETWORK, ShelfConnector.Permission.READ_LIBRARY)
        val connectors = ShelfConnectors(listOf(connector(some)), choices)
        assertFalse(connectors.isOn("x"))
        refuses(ShelfError.SourceOff) { connectors.source("x") }
        refuses(ShelfError.SourceOff) { connectors.turnOn("x", setOf(ShelfConnector.Permission.NETWORK)) }
        refuses(ShelfError.SourceOff) { connectors.turnOn("unknown", some) }
        assertEquals(0, opened)
        connectors.turnOn("x", some)
        connectors.source("x")
        assertEquals(1, opened)
        // A version that asks for more is off again, and a build of the app without it does not know it any more.
        assertFalse(ShelfConnectors(listOf(connector(ShelfConnector.Permission.entries.toSet())), choices).isOn("x"))
        assertFalse(ShelfConnectors(emptyList(), choices).isOn("x"))
        connectors.turnOff("x")
        assertFalse(connectors.isOn("x"))
        assertEquals(1, forgotten)
    }
}
