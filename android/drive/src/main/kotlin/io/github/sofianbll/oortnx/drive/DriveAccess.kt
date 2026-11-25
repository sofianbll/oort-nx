package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfCrypto
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfStop
import io.github.sofianbll.oortnx.shelf.fail
import io.github.sofianbll.oortnx.shelf.jsonObject
import java.io.File
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.URI
import java.net.URISyntaxException
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.SecureRandom
import java.util.Base64
import java.util.UUID

/** The player's own Google client. Nobody else's: Oort has none, and the Mac's token never travels. */
data class DriveClient(
    val id: String,
    val kind: Kind,
    /** Google gives desktop clients one and says it is not confidential. Never present for [Kind.IOS]. */
    internal val secret: DriveSecret?,
) {
    /** IOS: no secret, Google answers on a private address of the app. DESKTOP: Google answers on 127.0.0.1 (Android). */
    enum class Kind(val id: String) { IOS("ios"), DESKTOP("desktop") }
}

/** What the Mac shows as a code to scan: which client, which folder, whose builds to trust. It opens nothing by itself. */
class DriveInvite(val client: DriveClient, /** Identifier of the library folder. */ val folder: String, /** The Mac's public key: the only signer. */ val signer: ByteArray) {
    companion object {
        private const val LIMIT = 1024
        private val KEYS = setOf("oort", "kind", "client", "secret", "folder", "signer")
        private val CLIENT = Regex("[A-Za-z0-9][A-Za-z0-9-]{0,127}\\.apps\\.googleusercontent\\.com")
        private val SECRET = Regex("[A-Za-z0-9_-]{1,128}")

        /** Null for anything unexpected. A code that carries a token is refused, so that a Mac can never learn to send one. */
        fun parse(text: String): DriveInvite? {
            val data = text.toByteArray()
            if (data.size > LIMIT) return null
            val map = Json.read(data).jsonObject() ?: return null
            if (!KEYS.containsAll(map.keys) || map.values.any { it !is String } || map["oort"] != "drive-1") return null
            val kind = DriveClient.Kind.entries.firstOrNull { it.id == map["kind"] } ?: return null
            val id = (map["client"] as? String)?.takeIf { CLIENT.matches(it) } ?: return null
            val folder = (map["folder"] as? String)?.takeIf { DriveSource.isID(it) } ?: return null
            val signer = try {
                Base64.getDecoder().decode(map["signer"] as? String ?: return null)
            } catch (_: IllegalArgumentException) {
                return null
            }
            if (ShelfCrypto.publicKey(signer) == null) return null
            val secret = map["secret"] as String?
            if (secret != null && (kind != DriveClient.Kind.DESKTOP || !SECRET.matches(secret))) return null
            return DriveInvite(DriveClient(id, kind, secret?.let { DriveSecret(it) }), folder, signer)
        }
    }
}

/** Google's addresses. Nothing else is ever contacted. */
class DriveEndpoints(val authorize: String, val token: String, val files: String) {
    val hosts: List<String> get() = listOf(authorize, token, files).map { URI(it).host }.distinct().sorted()

    companion object {
        val google = DriveEndpoints("https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token", "https://www.googleapis.com/drive/v3/files")
    }
}

/** The sign-in page's address, and what comes back from it. The browser itself belongs to the app. One per sign-in. */
class DriveSignIn internal constructor(
    val client: DriveClient,
    internal val verifier: DriveSecret,
    internal val state: DriveSecret,
    internal val redirect: String,
    private val endpoints: DriveEndpoints,
) {
    internal constructor(client: DriveClient, receiver: DriveReceiver, endpoints: DriveEndpoints = DriveEndpoints.google) :
        this(client, DriveSecret(random()), DriveSecret(random()), receiver.address, endpoints)

    val page: String
        get() = endpoints.authorize + "?" + listOf(
            "client_id" to client.id, "redirect_uri" to redirect, "response_type" to "code", "scope" to SCOPE,
            "code_challenge" to challenge(verifier.reveal()), "code_challenge_method" to "S256", "state" to state.reveal(),
        ).joinToString("&") { (name, value) -> name + "=" + URLEncoder.encode(value, "UTF-8") }

    /** The code in the address Google came back on, only for this very request. */
    internal fun code(callback: String): DriveSecret {
        val came = try { URI(callback) } catch (_: URISyntaxException) { fail(ShelfError.BadResponse) }
        val asked = URI(redirect)
        if (came.scheme != asked.scheme || came.host != asked.host || came.port != asked.port || came.path.orEmpty().ifEmpty { "/" } != asked.path.orEmpty().ifEmpty { "/" }) fail(ShelfError.BadResponse)
        val items = try {
            came.rawQuery.orEmpty().split("&").map { it.substringBefore("=") to URLDecoder.decode(it.substringAfter("=", ""), "UTF-8") }
        } catch (_: IllegalArgumentException) {
            fail(ShelfError.BadResponse)
        }
        fun only(name: String) = items.filter { it.first == name }.singleOrNull()?.second
        if (only("state") != state.reveal()) fail(ShelfError.BadResponse)
        if (items.any { it.first == "error" }) fail(ShelfError.AccessDenied)
        return DriveSecret(only("code")?.takeIf { it.isNotEmpty() } ?: fail(ShelfError.BadResponse))
    }

    companion object {
        /** Reading only. Nothing wider is ever asked for or accepted. */
        const val SCOPE = "https://www.googleapis.com/auth/drive.readonly"

        internal fun challenge(verifier: String): String =
            Base64.getUrlEncoder().withoutPadding().encodeToString(ShelfCrypto.sha256().digest(verifier.toByteArray()))

        internal fun random(): String = Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(48).also { SecureRandom().nextBytes(it) })
    }
}

/** Waits on 127.0.0.1 for the browser to come back, once. Nothing outside the device can reach it. */
class DriveReceiver : AutoCloseable {
    private val socket = ServerSocket(0, 4, InetAddress.getByAddress(byteArrayOf(127, 0, 0, 1)))

    /** A port the system chose for this sign-in. */
    val address: String = "http://127.0.0.1:${socket.localPort}"

    /** The address the browser asked for. Anything that does not carry this sign-in's state is turned away and waited past. */
    fun receive(signIn: DriveSignIn, stop: ShelfStop, seconds: Int = 600): String = stop.during({ close() }) {
        val end = System.nanoTime() + seconds * 1_000_000_000L
        try {
            while (true) {
                val left = (end - System.nanoTime()) / 1_000_000
                if (left <= 0) fail(ShelfError.Interrupted)
                socket.soTimeout = left.toInt()
                socket.accept().use { client ->
                    client.soTimeout = 5_000
                    val path = try { requested(client.getInputStream()) } catch (_: IOException) { null }
                    val callback = path?.let { address + it }
                    val isOurs = callback != null && try {
                        signIn.code(callback)
                        true
                    } catch (failure: ShelfException) {
                        failure.error == ShelfError.AccessDenied
                    }
                    val text = if (isOurs) "You can go back to Oort NX." else "Not found."
                    try {
                        client.getOutputStream().write(
                            ("HTTP/1.1 ${if (isOurs) "200 OK" else "404 Not Found"}\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\n" +
                                "Referrer-Policy: no-referrer\r\nContent-Length: ${text.length}\r\nConnection: close\r\n\r\n$text").toByteArray(),
                        )
                    } catch (_: IOException) {
                        // The browser went away; the answer is what matters.
                    }
                    if (isOurs) return@during callback
                }
            }
            @Suppress("UNREACHABLE_CODE") ""
        } catch (_: SocketTimeoutException) {
            fail(ShelfError.Interrupted)
        } catch (_: SocketException) {
            stop.check()
            fail(ShelfError.Interrupted)
        }
    }

    private fun requested(input: java.io.InputStream): String? {
        val line = StringBuilder()
        while (line.length < 4096) {
            val c = input.read()
            if (c < 0 || c == '\n'.code) break
            line.append(c.toChar())
        }
        val parts = line.trim().split(" ")
        return parts.getOrNull(1)?.takeIf { parts.size == 3 && parts[0] == "GET" && it.startsWith("/") }
    }

    override fun close() = socket.close()
}

/** The one place that holds the access token, in memory only, and renews it. */
class DriveAccess internal constructor(
    private val client: DriveClient,
    private val vault: DriveVault,
    private val transport: DriveTransport,
    private val endpoints: DriveEndpoints,
    private val scratch: File,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private var current: DriveSecret? = null
    private var until = 0L

    /** [refused]: a token the source just turned down. Two requests refused together renew once. */
    @Synchronized
    internal fun token(refused: DriveSecret?, stop: ShelfStop): DriveSecret {
        current?.let { if (it != refused && until > now()) return it }
        return renew(stop)
    }

    /** Ends a sign-in. The refresh token goes straight to the vault. */
    @Synchronized
    fun finish(signIn: DriveSignIn, callback: String, stop: ShelfStop = ShelfStop()) {
        val code = signIn.code(callback)
        val answer = ask(
            mapOf(
                "grant_type" to "authorization_code", "code" to code.reveal(), "code_verifier" to signIn.verifier.reveal(),
                "redirect_uri" to signIn.redirect, "client_id" to client.id,
            ),
            stop,
        )
        if (answer.scope != DriveSignIn.SCOPE || answer.refresh.isNullOrEmpty()) fail(ShelfError.AccessDenied)
        vault.write(DriveSecret(answer.refresh))
        keep(answer)
    }

    /**
     * Erases what this device holds. Google's own list of connections is where the player withdraws the permission itself: Google's
     * revocation call would cut every client of the same project, the Mac's included.
     */
    @Synchronized
    fun forget() {
        current = null
        vault.erase()
    }

    private class Answer(val access: String, val seconds: Long, val scope: String?, val refresh: String?)

    private fun renew(stop: ShelfStop): DriveSecret {
        val refresh = vault.read() ?: fail(ShelfError.SignInNeeded)
        try {
            val answer = ask(mapOf("grant_type" to "refresh_token", "refresh_token" to refresh.reveal(), "client_id" to client.id), stop)
            if (answer.scope != null && answer.scope != DriveSignIn.SCOPE) fail(ShelfError.AccessDenied)
            answer.refresh?.let { vault.write(DriveSecret(it)) }
            return keep(answer)
        } catch (failure: ShelfException) {
            if (failure.error == ShelfError.SignInNeeded) {
                // Google will not take it again.
                current = null
                vault.erase()
            }
            throw failure
        }
    }

    private fun keep(answer: Answer): DriveSecret {
        until = now() + maxOf(0, answer.seconds - 60) * 1000
        return DriveSecret(answer.access).also { current = it }
    }

    private fun ask(fields: Map<String, String>, stop: ShelfStop): Answer {
        val all = client.secret?.let { fields + ("client_secret" to it.reveal()) } ?: fields
        val body = all.toSortedMap().entries.joinToString("&") { (name, value) -> name + "=" + URLEncoder.encode(value, "UTF-8") }
        scratch.mkdirs()
        val file = File(scratch, UUID.randomUUID().toString())
        try {
            val reply = transport.send(DriveRequest(endpoints.token, mapOf("Content-Type" to "application/x-www-form-urlencoded"), body.toByteArray()), file, 64 * 1024, stop)
            when (reply.status) {
                200 -> {
                    val map = Json.read(file.readBytes()).jsonObject() ?: fail(ShelfError.BadResponse)
                    val access = map["access_token"] as? String
                    val seconds = (map["expires_in"] as? Number)?.toLong()
                    if (access.isNullOrEmpty() || seconds == null || map["token_type"] != "Bearer") fail(ShelfError.BadResponse)
                    return Answer(access, seconds, map["scope"] as? String, map["refresh_token"] as? String)
                }
                400, 401 -> fail(ShelfError.SignInNeeded)
                429 -> fail(ShelfError.Busy(reply.header("Retry-After")?.toIntOrNull()))
                in 500..599 -> fail(ShelfError.Server)
                else -> fail(ShelfError.BadResponse)
            }
        } catch (_: IOException) {
            fail(ShelfError.LocalFile)
        } finally {
            file.delete()
        }
    }
}
