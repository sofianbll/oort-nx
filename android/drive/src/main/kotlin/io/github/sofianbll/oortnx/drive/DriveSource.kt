package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfConnector
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfNode
import io.github.sofianbll.oortnx.shelf.ShelfSource
import io.github.sofianbll.oortnx.shelf.ShelfStop
import io.github.sofianbll.oortnx.shelf.fail
import io.github.sofianbll.oortnx.shelf.jsonObject
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

/** Google Drive as a library source: two calls, `files.list` and `files.get`, with a read-only scope. Nothing here can write. */
internal class DriveSource(
    override val root: String,
    private val access: DriveAccess,
    private val transport: DriveTransport,
    private val endpoints: DriveEndpoints,
    private val scratch: File,
) : ShelfSource {
    private class PageRefused : Exception()

    override fun children(folder: String, stop: ShelfStop): List<ShelfNode> {
        if (!isID(folder)) fail(ShelfError.BadResponse)
        // "If the token is rejected for any reason, it should be discarded, and pagination should be restarted."
        repeat(2) {
            try {
                return pages(folder, stop)
            } catch (_: PageRefused) {
                // Once more from the first page.
            }
        }
        fail(ShelfError.BadResponse)
    }

    private fun pages(folder: String, stop: ShelfStop): List<ShelfNode> {
        val nodes = mutableListOf<ShelfNode>()
        val seen = HashSet<String>()
        var token: String? = null
        repeat(MAXIMUM_PAGES) {
            val query = listOfNotNull(
                "q" to "'$folder' in parents and trashed = false",
                "fields" to "nextPageToken,incompleteSearch,files(id,name,mimeType,size,sha256Checksum,md5Checksum)",
                "pageSize" to "1000", "supportsAllDrives" to "true", "includeItemsFromAllDrives" to "true", token?.let { "pageToken" to it },
            ).joinToString("&") { (name, value) -> name + "=" + URLEncoder.encode(value, "UTF-8") }
            val data = send(DriveRequest(endpoints.files + "?" + query), LIST_LIMIT, 200, stop, { if (it == 400 && token != null) throw PageRefused() }) { _, body -> body.readBytes() }
            val page = Json.read(data).jsonObject() ?: fail(ShelfError.BadResponse)
            val files = page["files"] as? List<*> ?: fail(ShelfError.BadResponse)
            if (page["incompleteSearch"] == true) fail(ShelfError.BadResponse)
            files.mapTo(nodes) { node(it.jsonObject() ?: fail(ShelfError.BadResponse)) }
            val next = page["nextPageToken"] as? String
            if (next.isNullOrEmpty()) return nodes
            if (!seen.add(next)) fail(ShelfError.BadResponse)
            token = next
        }
        fail(ShelfError.BadResponse)
    }

    private fun node(file: Map<String, Any?>): ShelfNode {
        val id = (file["id"] as? String)?.takeIf { isID(it) } ?: fail(ShelfError.BadResponse)
        val name = file["name"] as? String ?: fail(ShelfError.BadResponse)
        val type = file["mimeType"] as? String ?: fail(ShelfError.BadResponse)
        val kind = when {
            type == "application/vnd.google-apps.folder" -> ShelfNode.Kind.FOLDER
            type.startsWith("application/vnd.google-apps.") -> ShelfNode.Kind.OTHER
            else -> ShelfNode.Kind.FILE
        }
        val size = file["size"]?.let { (it as? String)?.toLongOrNull()?.takeIf { n -> n >= 0 } ?: fail(ShelfError.BadResponse) }
        return ShelfNode(id, name, kind, size, (file["sha256Checksum"] as? String)?.lowercase(), (file["md5Checksum"] as? String)?.lowercase())
    }

    override fun fetch(file: ShelfNode, first: Long, count: Long, destination: File, stop: ShelfStop) {
        val size = file.size
        if (!isID(file.id) || count <= 0 || first < 0 || size == null || count > size - first) fail(ShelfError.BadResponse)
        // `acknowledgeAbuse` is never sent: a file Drive calls abusive stays where it is.
        val request = DriveRequest(endpoints.files + "/" + file.id + "?alt=media&supportsAllDrives=true", mapOf("Range" to "bytes=$first-${first + count - 1}"))
        send(request, count, 206, stop) { reply, body ->
            val range = reply.header("Content-Range")?.let { RANGE.matchEntire(it) } ?: fail(ShelfError.BadResponse)
            if (range.groupValues[3].toLong() != size) fail(ShelfError.WrongSize)
            if (range.groupValues[1].toLong() != first || range.groupValues[2].toLong() != first + count - 1) fail(ShelfError.BadResponse)
            if (body.length() != count) fail(ShelfError.Interrupted)
            Files.move(body.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE)
        }
    }

    private fun <T> send(request: DriveRequest, limit: Long, accepted: Int, stop: ShelfStop, special: (Int) -> Unit = {}, read: (DriveReply, File) -> T): T {
        scratch.mkdirs()
        var refused: DriveSecret? = null
        while (true) {
            val token = access.token(refused, stop)
            val body = File(scratch, UUID.randomUUID().toString())
            try {
                // An error body may be longer than the range.
                val authorized = DriveRequest(request.url, request.headers + ("Authorization" to "Bearer " + token.reveal()))
                val reply = transport.send(authorized, body, maxOf(limit, 64 * 1024), stop)
                if (reply.status == 401 && refused == null) {
                    refused = token
                    continue
                }
                special(reply.status)
                if (reply.status != accepted) fail(failure(reply, body))
                if (reply.header("Content-Encoding").orEmpty() !in listOf("", "identity") || body.length() > limit) fail(ShelfError.BadResponse)
                return read(reply, body)
            } catch (_: IOException) {
                fail(ShelfError.LocalFile)
            } finally {
                body.delete()
            }
        }
    }

    /** Only Drive's reason word is read; its message may repeat the request. */
    private fun failure(reply: DriveReply, body: File): ShelfError {
        val errors = Json.read(body.readBytes()).jsonObject()?.get("error").jsonObject()?.get("errors") as? List<*>
        val reason = errors?.firstOrNull().jsonObject()?.get("reason") as? String
        val after = reply.header("Retry-After")?.toIntOrNull()
        return when (reply.status) {
            401 -> ShelfError.SignInNeeded
            403 -> when (reason) {
                "rateLimitExceeded", "userRateLimitExceeded" -> ShelfError.Busy(after)
                "dailyLimitExceeded", "downloadQuotaExceeded", "quotaExceeded" -> ShelfError.QuotaExceeded
                else -> ShelfError.AccessDenied
            }
            404 -> ShelfError.NotFound
            416 -> ShelfError.WrongSize
            429 -> ShelfError.Busy(after)
            in 500..599 -> ShelfError.Server
            else -> ShelfError.BadResponse
        }
    }

    companion object {
        private const val LIST_LIMIT = 8L shl 20
        private const val MAXIMUM_PAGES = 200
        private val ID = Regex("[A-Za-z0-9_][A-Za-z0-9_-]{0,127}")
        private val RANGE = Regex("bytes (\\d{1,18})-(\\d{1,18})/(\\d{1,18})")

        fun isID(text: String): Boolean = text != "root" && text != "appDataFolder" && ID.matches(text)
    }
}

/** The optional connector, off until the player turns it on. An app that does not list it cannot reach Google. */
class DriveConnection internal constructor(
    private val invite: DriveInvite,
    private val vault: DriveVault,
    transport: DriveTransport,
    private val endpoints: DriveEndpoints,
    scratch: File,
) {
    /** [endpoints]: Google's, but in a build made for checks. */
    constructor(invite: DriveInvite, vault: DriveVault, scratch: File, endpoints: DriveEndpoints = DriveEndpoints.google) :
        this(invite, vault, DriveHttp, endpoints, scratch)

    fun signIn(receiver: DriveReceiver) = DriveSignIn(invite.client, receiver, endpoints)

    /** Whether this device holds a sign-in. Asks nothing of the network. */
    val isSignedIn: Boolean get() = vault.read() != null

    /** For the sign-in screen. */
    val access = DriveAccess(invite.client, vault, transport, endpoints, scratch)

    val connector = ShelfConnector(
        ID, endpoints.hosts, ShelfConnector.Permission.entries.toSet(),
        open = { DriveSource(invite.folder, access, transport, endpoints, scratch) }, forget = { access.forget() },
    )

    companion object {
        const val ID = "google-drive"

        /** The hosts and the permissions, for the screen that asks before any code is known. */
        val outline = ShelfConnector(ID, DriveEndpoints.google.hosts, ShelfConnector.Permission.entries.toSet(),
            open = { fail(ShelfError.SourceOff) }, forget = {})
    }
}
