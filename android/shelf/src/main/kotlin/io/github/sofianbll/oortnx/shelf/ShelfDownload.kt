package io.github.sofianbll.oortnx.shelf

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.BasicFileAttributes

data class ShelfProgress(val received: Long, val total: Long)

/**
 * Where downloads live on the device. Everything waits in `.incoming` and only a whole, checked build gets a visible folder.
 * Give it a folder Android never backs up (`noBackupFilesDir`): a build can always be read again from the source.
 */
class ShelfStore(val root: File, internal val available: (File) -> Long? = { it.freeBytes() }) {
    fun visible(build: ShelfBuild): File = File(File(root, build.titleID), build.digest)

    /** Where a download waits; it exists while one is stopped half-way. */
    fun waiting(build: ShelfBuild): File = File(File(root, ".incoming"), "${build.titleID}-${build.platform.id}-${build.digest}")

    /** Forgets what a stopped download kept. The visible copy, if any, stays. */
    fun discard(build: ShelfBuild) {
        waiting(build).deleteRecursively()
    }

    /** The digest that is visible for each title: what [ShelfCatalog.list] takes as `installed`. The newest folder wins. */
    fun installed(): Map<String, String> = (root.listFiles() ?: emptyArray()).filter { ShelfNames.isTitleID(it.name) }.mapNotNull { folder ->
        (folder.listFiles() ?: emptyArray()).filter { ShelfNames.isHex(it.name, 64) }
            .maxWithOrNull(compareBy({ it.lastModified() }, { it.name }))?.let { folder.name to it.name }
    }.toMap()

    private companion object {
        fun File.freeBytes(): Long? = generateSequence(this) { it.parentFile }.firstOrNull { it.exists() }?.usableSpace
    }
}

/** The player's rules for a source. */
data class ShelfRules(
    val allowsMeteredNetwork: Boolean = false,
    /** One request's worth: what a broken connection can lose. */
    val chunk: Long = 16L shl 20,
    /** Left free on the device beyond the build itself. */
    val reserve: Long = 256L shl 20,
)

/** Brings one build onto the device. Stop it at any moment and run it again: it asks only for the ranges that are missing. */
class ShelfDownload(
    private val source: ShelfSource,
    private val store: ShelfStore,
    private val rules: ShelfRules = ShelfRules(),
    private val retry: ShelfRetry = ShelfRetry.standard,
    private val isMetered: () -> Boolean,
) {
    /** Returns the visible folder. Stopping keeps what was received. */
    fun run(build: ShelfBuild, stop: ShelfStop = ShelfStop(), progress: (ShelfProgress) -> Unit = {}): File {
        val visible = store.visible(build)
        if (visible.exists()) return visible
        val waiting = store.waiting(build)
        val tree = File(waiting, "tree")
        val parts = File(waiting, "parts")
        checkNetwork()
        // What is already here, before asking the source anything.
        val kept = HashMap<Int, Long>()
        var received = 0L
        for ((index, entry) in build.entries.withIndex()) {
            if (size(File(tree, entry.path)) == entry.size) {
                received += entry.size
                continue
            }
            val part = File(parts, "$index.part")
            val length = size(part) ?: 0
            if (length > entry.size) part.delete()
            kept[index] = if (length > entry.size) 0 else length
            received += kept.getValue(index)
        }
        checkSpace(build.bytes - received)
        val nodes = locate(build, stop)
        local {
            Files.createDirectories(tree.toPath())
            Files.createDirectories(parts.toPath())
        }
        progress(ShelfProgress(received, build.bytes))
        for ((index, entry) in build.entries.withIndex()) {
            var offset = kept[index] ?: continue
            val node = nodes.getValue(entry.path)
            val part = File(parts, "$index.part")
            val chunk = File(parts, "$index.chunk")
            while (offset < entry.size) {
                stop.check()
                checkNetwork()
                checkSpace(build.bytes - received)
                val count = minOf(rules.chunk, entry.size - offset)
                retry.run(stop) {
                    chunk.delete()
                    source.fetch(node, offset, count, chunk, stop)
                }
                if (size(chunk) != count) {
                    chunk.delete()
                    fail(ShelfError.WrongSize)
                }
                local { append(chunk, part) }
                offset += count
                received += count
                progress(ShelfProgress(received, build.bytes))
            }
            stop.check()
            local {
                if (entry.size == 0L) part.writeBytes(ByteArray(0))
                if (digest(part, stop) != entry.sha256) {
                    part.delete()
                    fail(ShelfError.WrongDigest)
                }
                val file = File(tree, entry.path)
                Files.createDirectories(file.parentFile!!.toPath())
                Files.move(part.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE)
            }
        }
        local {
            if (!build.entries.all { size(File(tree, it.path)) == it.size }) fail(ShelfError.WrongSize)
            Files.createDirectories(visible.parentFile!!.toPath())
            // One rename on one volume: the build appears whole, or not at all.
            Files.move(tree.toPath(), visible.toPath(), StandardCopyOption.ATOMIC_MOVE)
            waiting.deleteRecursively()
        }
        return visible
    }

    /** Finds every file of the build, and refuses a tree that does not match its manifest before downloading a byte of it. */
    private fun locate(build: ShelfBuild, stop: ShelfStop): Map<String, ShelfNode> {
        val root = build.folder ?: fail(ShelfError.FilesMissing)
        val wanted = build.entries.associateBy { it.path }
        val folders = HashSet<String>()
        for (entry in build.entries) {
            val pieces = entry.path.split("/").dropLast(1)
            for (count in 1..pieces.size) folders.add(pieces.take(count).joinToString("/"))
        }
        val found = HashMap<String, ShelfNode>()
        val queue = ArrayDeque(listOf(root to ""))
        var count = 0
        while (queue.isNotEmpty()) {
            val (id, path) = queue.removeFirst()
            val nodes = retry.run(stop) { source.children(id, stop) }
            count += nodes.size
            if (count > MAXIMUM_NODES) fail(ShelfError.BadResponse)
            val names = nodes.groupingBy { ShelfNames.folded(it.name) }.eachCount()
            for (node in nodes) {
                val full = if (path.isEmpty()) node.name else "$path/${node.name}"
                val entry = wanted[full]
                // Only the folders the manifest names are opened; anything else in there is left alone.
                if (entry == null && full !in folders) continue
                if (names[ShelfNames.folded(node.name)] != 1) fail(ShelfError.Ambiguous)
                if (entry != null) {
                    if (node.kind != ShelfNode.Kind.FILE) fail(ShelfError.FilesMissing)
                    if (node.size != entry.size) fail(ShelfError.WrongSize)
                    if (node.sha256 != null && node.sha256 != entry.sha256) fail(ShelfError.WrongDigest)
                    found[full] = node
                } else {
                    if (node.kind != ShelfNode.Kind.FOLDER) fail(ShelfError.FilesMissing)
                    queue.add(node.id to full)
                }
            }
        }
        if (found.size != wanted.size) fail(ShelfError.FilesMissing)
        return found
    }

    private fun checkNetwork() {
        if (!rules.allowsMeteredNetwork && isMetered()) fail(ShelfError.NetworkNotAllowed)
    }

    private fun checkSpace(remaining: Long) {
        // A chunk is held twice while it is added to its file.
        val needed = remaining + minOf(rules.chunk, remaining) + rules.reserve
        val free = store.available(store.root) ?: return
        if (free < needed) fail(ShelfError.NoSpace(needed))
    }

    /** Null for anything that is not a plain file: a link is never followed. */
    private fun size(file: File): Long? = try {
        Files.readAttributes(file.toPath(), BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS).takeIf { it.isRegularFile }?.size()
    } catch (_: IOException) {
        null
    }

    private fun append(chunk: File, part: File) {
        if (size(part) == null) {
            Files.move(chunk.toPath(), part.toPath(), StandardCopyOption.ATOMIC_MOVE)
            return
        }
        val start = part.length()
        try {
            FileOutputStream(part, true).use { output ->
                chunk.inputStream().use { it.copyTo(output, 1 shl 20) }
                output.fd.sync()
            }
        } catch (failure: IOException) {
            // A half-added chunk would shift everything after it.
            RandomAccessFile(part, "rw").use { it.setLength(start) }
            throw failure
        }
        chunk.delete()
    }

    private fun digest(file: File, stop: ShelfStop): String {
        val hash = ShelfCrypto.sha256()
        val buffer = ByteArray(1 shl 20)
        file.inputStream().use { input ->
            while (true) {
                stop.check()
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().hex()
    }

    private companion object {
        /** A tree larger than this is not a build. */
        const val MAXIMUM_NODES = 100_000

        /** A full disk is told apart; a path never leaves the device in an error. */
        fun <T> local(body: () -> T): T = try {
            body()
        } catch (failure: IOException) {
            val full = generateSequence<Throwable>(failure) { it.cause }.any { it.message.orEmpty().let { text -> "ENOSPC" in text || "No space left" in text } }
            fail(if (full) ShelfError.NoSpace(0) else ShelfError.LocalFile)
        }
    }
}
