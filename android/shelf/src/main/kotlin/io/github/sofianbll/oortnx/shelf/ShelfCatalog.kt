package io.github.sofianbll.oortnx.shelf

import java.io.File
import java.io.IOException
import java.text.Normalizer
import java.util.Locale
import java.util.UUID

data class ShelfGame(val build: ShelfBuild, val state: State) {
    enum class State(val id: String) { AVAILABLE("available"), INSTALLED("installed"), UPDATE("update") }

    val titleID: String get() = build.titleID
    val name: String get() = build.name
}

/** A game of the library that this device does not show, and why. */
data class ShelfHidden(val titleID: String, val name: String, val reason: Reason) {
    enum class Reason(val id: String) {
        NOT_PREPARED("notPrepared"), SYSTEM("system"), GRAPHICS("graphics"), LAUNCHER("launcher"), FILES_MISSING("filesMissing")
    }
}

data class ShelfProblem(val titleID: String, val error: ShelfError)

data class ShelfListing(val games: List<ShelfGame>, val hidden: List<ShelfHidden>, val problems: List<ShelfProblem>)

enum class ShelfOrder(val id: String) { NAME("name"), NEWEST("newest"), SIZE("size") }

/** Reads a library folder the way the Mac lays it out, and keeps what runs on this device. */
class ShelfCatalog(
    private val source: ShelfSource,
    private val crypto: ShelfCrypto,
    private val scratch: File,
    private val retry: ShelfRetry = ShelfRetry.standard,
    private val stop: ShelfStop = ShelfStop(),
) {
    /** One damaged game is a problem of that game; a source that cannot answer stops the whole list. [installed] maps a title to its digest. */
    fun list(device: ShelfDevice, installed: Map<String, String> = emptyMap(), order: ShelfOrder = ShelfOrder.NAME): ShelfListing {
        val root = children(source.root)
        val names = root.groupingBy { ShelfNames.folded(it.name) }.eachCount()
        val folders = sortedMapOf<String, MutableList<ShelfNode>>()
        for (node in root) if (node.kind == ShelfNode.Kind.FOLDER) ShelfNames.titleID(node.name)?.let { folders.getOrPut(it) { mutableListOf() }.add(node) }
        if (folders.size > MAXIMUM_GAMES) fail(ShelfError.BadResponse)
        val games = mutableListOf<ShelfGame>()
        val hidden = mutableListOf<ShelfHidden>()
        val problems = mutableListOf<ShelfProblem>()
        for ((title, nodes) in folders) {
            stop.check()
            try {
                if (nodes.any { names[ShelfNames.folded(it.name)] != 1 }) fail(ShelfError.Ambiguous)
                when (val found = best(title, nodes, device) { problems.add(ShelfProblem(title, it)) }) {
                    is Found.Build -> {
                        val state = when (installed[title]) {
                            null -> ShelfGame.State.AVAILABLE
                            found.build.digest -> ShelfGame.State.INSTALLED
                            else -> ShelfGame.State.UPDATE
                        }
                        games.add(ShelfGame(found.build, state))
                    }
                    is Found.Hidden -> {
                        val folder = (nodes.firstOrNull { it.name != title } ?: nodes[0]).name
                        hidden.add(ShelfHidden(title, found.name ?: ShelfNames.displayName(folder, title), found.reason))
                    }
                    Found.Nothing -> Unit
                }
            } catch (failure: ShelfException) {
                if (!failure.error.isAboutOneGame) throw failure
                problems.add(ShelfProblem(title, failure.error))
            }
        }
        return ShelfListing(sorted(games, order), hidden, problems)
    }

    /** The Mac's newest app of a game, across its snapshots: an app kept from an older snapshot keeps its own date. */
    fun macBuild(titleID: String): ShelfMacBuild? {
        val found = mutableListOf<Pair<ShelfNames.Stamped, ShelfNode>>()
        for (folder in children(source.root)) {
            if (folder.kind != ShelfNode.Kind.FOLDER || ShelfNames.titleID(folder.name) != titleID) continue
            val manifests = children(folder.id).only("manifests", ShelfNode.Kind.FOLDER) ?: continue
            for (node in children(manifests.id)) if (node.kind == ShelfNode.Kind.FILE) ShelfNames.manifestName(node.name)?.let { found.add(it to node) }
        }
        var best: ShelfMacBuild? = null
        for ((name, node) in found.sortedByDescending { it.first }) {
            if (best != null && best.stamp >= name.stamp) break
            val build = ShelfMacBuild.read(read(node, ShelfMacBuild.MANIFEST_LIMIT), name, titleID, crypto)
            if (build != null && build.stamp > (best?.stamp ?: 0)) best = build
        }
        return best
    }

    private sealed interface Found {
        data class Build(val build: ShelfBuild) : Found
        data class Hidden(val reason: ShelfHidden.Reason, val name: String?) : Found
        data object Nothing : Found
    }

    private class Candidate(val name: ShelfNames.Stamped, val node: ShelfNode, val siblings: List<ShelfNode>)

    private fun best(title: String, folders: List<ShelfNode>, device: ShelfDevice, problem: (ShelfError) -> Unit): Found {
        var isOnMac = false
        var isElsewhere = false
        val candidates = mutableListOf<Candidate>()
        for (folder in folders) {
            val inside = children(folder.id)
            isOnMac = isOnMac || inside.only("manifests", ShelfNode.Kind.FOLDER) != null
            val targets = inside.only("targets", ShelfNode.Kind.FOLDER) ?: continue
            val platforms = children(targets.id)
            isElsewhere = isElsewhere || ShelfPlatform.entries.any { platform -> platforms.any { it.name == platform.id } }
            val own = platforms.only(device.platform.id, ShelfNode.Kind.FOLDER) ?: continue
            val siblings = children(own.id)
            for (node in siblings) if (node.kind == ShelfNode.Kind.FILE) ShelfNames.manifestName(node.name)?.let { candidates.add(Candidate(it, node, siblings)) }
        }
        candidates.sortByDescending { it.name }
        var refusal: Found.Hidden? = null
        for (candidate in candidates.take(OLDER_BUILDS)) {
            stop.check()
            try {
                val build = build(candidate, title, device)
                val reason = device.refusal(build)
                if (reason != null) {
                    refusal = refusal ?: Found.Hidden(reason, build.name)
                    continue
                }
                val folder = candidate.siblings.only(build.digest, ShelfNode.Kind.FOLDER)
                if (folder == null) {
                    refusal = refusal ?: Found.Hidden(ShelfHidden.Reason.FILES_MISSING, build.name)
                    continue
                }
                return Found.Build(build.copy(folder = folder.id))
            } catch (failure: ShelfException) {
                if (!failure.error.isAboutOneGame) throw failure
                problem(failure.error)
            }
        }
        if (refusal != null) return refusal
        return if (candidates.isEmpty() && (isOnMac || isElsewhere)) Found.Hidden(ShelfHidden.Reason.NOT_PREPARED, null) else Found.Nothing
    }

    private fun build(candidate: Candidate, title: String, device: ShelfDevice): ShelfBuild {
        val (node, siblings) = candidate.node to candidate.siblings
        if (siblings.count { ShelfNames.folded(it.name) == ShelfNames.folded(node.name) } != 1) fail(ShelfError.Ambiguous)
        val seal = siblings.only(node.name.removeSuffix(".json") + ".sig", ShelfNode.Kind.FILE) ?: fail(ShelfError.Unsigned)
        if ((seal.size ?: 0) !in 1..SIGNATURE_LIMIT) fail(ShelfError.Unsigned)
        val data = read(node, ShelfBuild.MANIFEST_LIMIT)
        val signature = read(seal, SIGNATURE_LIMIT)
        return ShelfBuild.read(data, signature, candidate.name, title, device.platform, crypto)
    }

    private fun children(folder: String): List<ShelfNode> = retry.run(stop) { source.children(folder, stop) }

    private fun read(node: ShelfNode, limit: Long): ByteArray {
        val size = node.size ?: 0
        if (size !in 1..limit) fail(ShelfError.InvalidManifest)
        scratch.mkdirs()
        val file = File(scratch, UUID.randomUUID().toString())
        try {
            retry.run(stop) {
                file.delete()
                source.fetch(node, 0, size, file, stop)
            }
            val data = file.readBytes()
            if (data.size.toLong() != size) fail(ShelfError.WrongSize)
            return data
        } catch (_: IOException) {
            fail(ShelfError.LocalFile)
        } finally {
            file.delete()
        }
    }

    companion object {
        const val MAXIMUM_GAMES = 2_000

        /** How many older builds are looked at when the newest does not run here. */
        private const val OLDER_BUILDS = 8
        private const val SIGNATURE_LIMIT = 512L
        private val MARKS = Regex("\\p{Mn}")

        fun sorted(games: List<ShelfGame>, order: ShelfOrder): List<ShelfGame> {
            // Accents and case do not count; no language rule, so both phones agree.
            fun key(game: ShelfGame) = Normalizer.normalize(game.name, Normalizer.Form.NFD).replace(MARKS, "").lowercase(Locale.ROOT).toByteArray()
            val byName = Comparator<ShelfGame> { a, b ->
                val left = key(a)
                val right = key(b)
                for (i in 0 until minOf(left.size, right.size)) {
                    val c = (left[i].toInt() and 0xFF).compareTo(right[i].toInt() and 0xFF)
                    if (c != 0) return@Comparator c
                }
                if (left.size != right.size) left.size.compareTo(right.size) else a.titleID.compareTo(b.titleID)
            }
            return games.sortedWith(
                when (order) {
                    ShelfOrder.NAME -> byName
                    ShelfOrder.NEWEST -> compareByDescending<ShelfGame> { it.build.stamp }.then(byName)
                    ShelfOrder.SIZE -> compareByDescending<ShelfGame> { it.build.bytes }.then(byName)
                },
            )
        }
    }
}
