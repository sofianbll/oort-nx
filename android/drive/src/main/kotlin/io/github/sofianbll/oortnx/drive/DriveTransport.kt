package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfException
import io.github.sofianbll.oortnx.shelf.ShelfStop
import io.github.sofianbll.oortnx.shelf.fail
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.NoRouteToHostException
import java.net.URI
import java.net.UnknownHostException
import java.util.concurrent.CancellationException
import javax.net.ssl.SSLException

internal class DriveRequest(val url: String, val headers: Map<String, String> = emptyMap(), val body: ByteArray? = null)

internal class DriveReply(val status: Int, private val headers: Map<String, String>) {
    fun header(name: String): String? = headers[name.lowercase()]
}

internal fun interface DriveTransport {
    /** Puts the answer's body in [file], a new file, and stops as soon as it passes [limit] bytes. */
    fun send(request: DriveRequest, file: File, limit: Long, stop: ShelfStop): DriveReply
}

/** The system's own HTTP client: no cookie, no cache, no redirection followed, no library. */
internal object DriveHttp : DriveTransport {
    override fun send(request: DriveRequest, file: File, limit: Long, stop: ShelfStop): DriveReply {
        val connection = URI(request.url).toURL().openConnection() as HttpURLConnection
        // A redirection would carry the credential elsewhere: the answer is given back as it is, and refused.
        connection.instanceFollowRedirects = false
        connection.useCaches = false
        connection.connectTimeout = 30_000
        connection.readTimeout = 30_000
        // Named explicitly, or Android would unpack a compressed body by itself.
        connection.setRequestProperty("Accept-Encoding", "identity")
        request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
        try {
            return stop.during({ connection.disconnect() }) { exchange(connection, request, file, limit, stop) }
        } catch (failure: IOException) {
            // The system's exceptions name the address: none is passed on, not even as a cause.
            stop.check()
            fail(
                when (failure) {
                    is UnknownHostException, is ConnectException, is NoRouteToHostException -> ShelfError.Offline
                    is SSLException -> ShelfError.BadResponse
                    else -> ShelfError.Interrupted
                },
            )
        } catch (failure: RuntimeException) {
            if (failure is CancellationException) throw failure
            fail(ShelfError.BadResponse)
        } finally {
            connection.disconnect()
        }
    }

    private fun exchange(connection: HttpURLConnection, request: DriveRequest, file: File, limit: Long, stop: ShelfStop): DriveReply {
        if (request.body != null) {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.outputStream.use { it.write(request.body) }
        }
        val status = connection.responseCode
        if (status < 0) throw IOException()
        val headers = HashMap<String, String>()
        connection.headerFields.forEach { (name, values) -> if (name != null) headers[name.lowercase()] = values.joinToString(", ") }
        val input = if (status >= 400) connection.errorStream else connection.inputStream
        val output = try { FileOutputStream(file) } catch (_: IOException) { throw ShelfException(ShelfError.LocalFile) }
        output.use {
            val buffer = ByteArray(1 shl 16)
            var total = 0L
            while (input != null) {
                stop.check()
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                if (total > limit) fail(ShelfError.BadResponse)
                try {
                    it.write(buffer, 0, count)
                } catch (failure: IOException) {
                    val full = failure.message.orEmpty().let { text -> "ENOSPC" in text || "No space left" in text }
                    fail(if (full) ShelfError.NoSpace(0) else ShelfError.LocalFile)
                }
            }
            val announced = headers["content-length"]?.toLongOrNull()
            if (announced != null && input != null && total < announced) throw IOException()
        }
        return DriveReply(status, headers)
    }
}
