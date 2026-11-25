package io.github.sofianbll.oortnx.shelf

import java.io.File
import java.util.concurrent.CancellationException

/** One entry of a library folder. Nothing here says which service holds it. */
data class ShelfNode(
    val id: String,
    val name: String,
    val kind: Kind,
    val size: Long? = null,
    val sha256: String? = null,
    val md5: String? = null,
) {
    /** [OTHER] is anything that is neither a plain file nor a folder (a shortcut, an online document): never followed, never read. */
    enum class Kind { FOLDER, FILE, OTHER }
}

/** Asks a blocking call to stop; what it received so far is kept. */
class ShelfStop {
    private val lock = Any()
    private var stopped = false
    private var hook: (() -> Unit)? = null

    val isStopped: Boolean get() = synchronized(lock) { stopped }

    fun stop() {
        val call = synchronized(lock) { stopped = true; hook }
        call?.invoke()
    }

    fun check() {
        if (isStopped) throw CancellationException("stopped")
    }

    /** Runs [body]; a stop in the meantime calls [onStop], for a call that blocks. */
    fun <T> during(onStop: () -> Unit, body: () -> T): T {
        synchronized(lock) {
            if (stopped) throw CancellationException("stopped")
            hook = onStop
        }
        try {
            return body()
        } finally {
            synchronized(lock) { hook = null }
        }
    }
}

/**
 * Where a phone reads the player's library: a cloud drive, a chosen folder, the Mac over Wi-Fi. Read only by construction: there is no
 * call that writes, renames or deletes. Every call blocks and belongs on a background thread.
 */
interface ShelfSource {
    /** The library's own folder. A source never reads above it. */
    val root: String

    /** Every child of the folder, all pages read. Throws rather than returning part of the list. */
    fun children(folder: String, stop: ShelfStop): List<ShelfNode>

    /** Writes exactly [count] bytes from [first] to [destination], which does not exist yet. [count] is never zero. */
    fun fetch(file: ShelfNode, first: Long, count: Long, destination: File, stop: ShelfStop)
}

/** Why a source or a download stopped. No address, no identifier and no credential, so any of them can be shown or logged. */
sealed class ShelfError(val code: String, val isTransient: Boolean = false) {
    /** The player has not turned this source on. */
    data object SourceOff : ShelfError("sourceOff")

    /** The player's rules do not allow this connection (mobile data). */
    data object NetworkNotAllowed : ShelfError("networkNotAllowed")
    data object Offline : ShelfError("offline")

    /** The connection broke on the way; the next try resumes. */
    data object Interrupted : ShelfError("interrupted", true)
    data object SignInNeeded : ShelfError("signInNeeded")
    data object AccessDenied : ShelfError("accessDenied")
    data object NotFound : ShelfError("notFound")

    /** The account has no download left for now; trying again at once would not help. */
    data object QuotaExceeded : ShelfError("quotaExceeded")
    data class Busy(val retryAfter: Int?) : ShelfError("busy", true)
    data object Server : ShelfError("server", true)

    /** The source answered something this code does not accept. */
    data object BadResponse : ShelfError("badResponse")
    data object Ambiguous : ShelfError("ambiguous")
    data object UnsafeName : ShelfError("unsafeName")
    data object InvalidManifest : ShelfError("invalidManifest")
    data object Unsigned : ShelfError("unsigned")
    data object FilesMissing : ShelfError("filesMissing")
    data object WrongSize : ShelfError("wrongSize")
    data object WrongDigest : ShelfError("wrongDigest")
    data class NoSpace(val needed: Long) : ShelfError("noSpace")
    data object LocalFile : ShelfError("localFile")

    val isAboutOneGame: Boolean
        get() = when (this) {
            Ambiguous, UnsafeName, InvalidManifest, Unsigned, FilesMissing, WrongSize, WrongDigest, NotFound -> true
            else -> false
        }
}

/** Carries no cause: a system exception may name an address or a path. */
class ShelfException(val error: ShelfError) : Exception(error.code)

fun fail(error: ShelfError): Nothing = throw ShelfException(error)

/** How often a transient failure is tried again. The waiting itself is injected, so a test never waits. */
class ShelfRetry(val attempts: Int = 4, private val wait: (Int, ShelfStop) -> Unit) {
    fun <T> run(stop: ShelfStop, body: () -> T): T {
        var attempt = 1
        while (true) {
            stop.check()
            try {
                return body()
            } catch (failure: ShelfException) {
                val error = failure.error
                if (!error.isTransient || attempt >= attempts) throw failure
                var seconds = minOf(1 shl (attempt - 1), 32)
                val asked = (error as? ShelfError.Busy)?.retryAfter
                if (asked != null) {
                    if (asked > LONGEST_WAIT) throw failure
                    seconds = maxOf(seconds, asked)
                }
                wait(seconds, stop)
                attempt++
            }
        }
    }

    companion object {
        const val LONGEST_WAIT = 60

        /** Seconds: 1, 2, 4… plus up to one second of jitter, or what the source asked for. */
        val standard = ShelfRetry { seconds, stop ->
            val end = System.nanoTime() + seconds * 1_000_000_000L + (Math.random() * 1_000_000_000L).toLong()
            while (System.nanoTime() < end) {
                stop.check()
                Thread.sleep(100)
            }
        }
    }
}
