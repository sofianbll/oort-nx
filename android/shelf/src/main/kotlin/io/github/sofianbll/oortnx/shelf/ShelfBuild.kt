package io.github.sofianbll.oortnx.shelf

import java.time.Instant
import java.time.format.DateTimeParseException

enum class ShelfPlatform(val id: String) { IOS("ios"), ANDROID("android") }

/**
 * A build of one game for one kind of device, as `targets/<platform>/<stamp>-<sha256>.json` describes it beside the Mac's archive.
 * The Mac's own app stays in its own manifests ([ShelfMacBuild]).
 */
data class ShelfBuild(
    val titleID: String,
    val name: String,
    val platform: ShelfPlatform,
    val gameVersion: String,
    val engineCommit: String,
    /** The oldest system that runs it: an API level on Android. */
    val minimumSystem: String,
    val architecture: String,
    /** What the graphics unit must offer, such as `bc`. A device that does not know a word does not have it. */
    val features: List<String>,
    /** The launcher-side contract it was built for. */
    val host: Int,
    /** The framework folder or the APK inside the build. */
    val packagePath: String,
    val packageID: String?,
    val packageVersion: Long?,
    val packageSigner: String?,
    val bytes: Long,
    val entries: List<Entry>,
    /** SHA-256 of the entries: the name of the folder that holds them. */
    val digest: String,
    /** Publication time in milliseconds: the newest build wins. */
    val stamp: Long,
    /** The source's identifier of that folder, null when it is not there. */
    val folder: String? = null,
) {
    data class Entry(val path: String, val size: Long, val sha256: String)

    companion object {
        const val MANIFEST_LIMIT = 16L * 1024 * 1024
        private const val MAXIMUM_ENTRIES = 50_000
        private const val SIGNED_PREFIX = "oort-target-1\n"
        private val PACKAGE_ID = Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+")

        /** Checks everything before anything is shown: the name, the content's hash, the signature, the paths and the sizes. */
        internal fun read(data: ByteArray, signature: ByteArray, name: ShelfNames.Stamped, titleID: String, platform: ShelfPlatform, crypto: ShelfCrypto): ShelfBuild {
            if (data.size > MANIFEST_LIMIT || crypto.digest(data) != name.sha256) fail(ShelfError.InvalidManifest)
            if (!crypto.isSigned(SIGNED_PREFIX.toByteArray() + data, signature)) fail(ShelfError.Unsigned)
            return parse(Fields(Json.read(data).jsonObject()), name.stamp, titleID, platform, crypto)
        }

        private fun parse(file: Fields, stamp: Long, titleID: String, platform: ShelfPlatform, crypto: ShelfCrypto): ShelfBuild {
            val requires = file.fields("requires")
            val pack = file.fields("package")
            val engine = file.fields("engine").text("commit")
            val version = file.text("game_version")
            val system = requires.text("os")
            val features = requires.list("features").map { it as? String ?: fail(ShelfError.InvalidManifest) }
            val host = requires.number("host")
            val entries = file.list("entries").map { item ->
                Fields(item.jsonObject()).let { Entry(it.text("path"), it.number("size"), it.text("sha256")) }
            }
            if (file.text("format") != "oort-target" || file.number("version") != 1L || file.text("title_id") != titleID ||
                file.text("platform") != platform.id || file.number("entry_count") != entries.size.toLong() ||
                entries.size !in 1..MAXIMUM_ENTRIES || !ShelfNames.isHex(engine, 40) || version.toByteArray().size !in 1..40 ||
                !ShelfNames.isPlain(version) || ShelfNames.compareVersions(system, "0") == null || host !in 0..Int.MAX_VALUE.toLong() ||
                features.size > 32
            ) fail(ShelfError.InvalidManifest)
            val bytes = total(entries)
            val digest = file.text("inventory_sha256")
            if (bytes != file.number("unpacked_size") || digest(entries, crypto) != digest) fail(ShelfError.InvalidManifest)
            val path = pack.text("path")
            val id = pack.optionalText("id")
            val code = pack.optionalNumber("version_code")
            val signer = pack.optionalText("certificate_sha256")
            val known = when (platform) {
                ShelfPlatform.IOS -> path.endsWith(".framework") && '/' !in path && entries.any { it.path.startsWith("$path/") }
                ShelfPlatform.ANDROID -> path.endsWith(".apk") && '/' !in path && entries.any { it.path == path } &&
                    id != null && PACKAGE_ID.matches(id) && code != null && code > 0 && ShelfNames.isHex(signer, 64)
            }
            if (!known) fail(ShelfError.InvalidManifest)
            return ShelfBuild(
                titleID, ShelfNames.displayName(file.text("game_name"), titleID), platform, version, engine, system, requires.text("arch"),
                features, host.toInt(), path, id, code, signer, bytes, entries, digest, stamp,
            )
        }

        /** The same bytes as the Mac's encoder: sorted keys, no spaces, slashes as they are. */
        private fun digest(entries: List<Entry>, crypto: ShelfCrypto): String = crypto.digest(
            entries.joinToString(",", "[", "]") { "{\"path\":${ShelfNames.quoted(it.path)},\"sha256\":\"${it.sha256}\",\"size\":${it.size}}" }.toByteArray(),
        )

        private fun total(entries: List<Entry>): Long {
            var bytes = 0L
            val seen = HashMap<String, Pair<String, Boolean>>()
            for (entry in entries) {
                if (!ShelfNames.isSafePath(entry.path)) fail(ShelfError.UnsafeName)
                if (entry.size < 0 || entry.size > Long.MAX_VALUE - bytes || !ShelfNames.isHex(entry.sha256, 64)) fail(ShelfError.InvalidManifest)
                bytes += entry.size
                // One spelling per name, and a name is a file or a folder, never both.
                var prefix = ""
                val parts = entry.path.split("/")
                for ((index, part) in parts.withIndex()) {
                    prefix += (if (prefix.isEmpty()) "" else "/") + part
                    val isFolder = index < parts.size - 1
                    val key = ShelfNames.folded(prefix)
                    val old = seen[key]
                    if (old == null) seen[key] = prefix to isFolder
                    else if (!isFolder || !old.second || old.first != prefix) fail(ShelfError.UnsafeName)
                }
            }
            return bytes
        }
    }
}

/** The device that asks. [features] and [host] are what it really has. */
data class ShelfDevice(val platform: ShelfPlatform, val system: String, val architecture: String, val features: Set<String>, val host: Int) {
    /** Why a build would not run here, null when it runs. */
    fun refusal(build: ShelfBuild): ShelfHidden.Reason? {
        if (build.platform != platform || build.architecture != architecture) return ShelfHidden.Reason.NOT_PREPARED
        val order = ShelfNames.compareVersions(build.minimumSystem, system)
        if (order == null || order > 0) return ShelfHidden.Reason.SYSTEM
        if (!features.containsAll(build.features)) return ShelfHidden.Reason.GRAPHICS
        return if (build.host == host) null else ShelfHidden.Reason.LAUNCHER
    }
}

/** What the Mac's own manifest (version 1 or 2) says of its app. The phone shows it as "on your Mac"; it never downloads it. */
data class ShelfMacBuild(
    val titleID: String,
    val name: String?,
    val gameVersion: String?,
    val engineCommit: String?,
    val bytes: Long,
    val stamp: Long,
) {
    companion object {
        const val MANIFEST_LIMIT = 32L * 1024 * 1024
        private const val LEGACY_LIMIT = 64 * 1024
        private val KINDS = setOf(listOf("app"), listOf("app", "cache"), emptyList(), listOf("cache"))

        /** Null when this snapshot holds no app. The checks are the Mac's own (CloudGameArchive.readManifest). */
        internal fun read(data: ByteArray, name: ShelfNames.Stamped, titleID: String, crypto: ShelfCrypto): ShelfMacBuild? {
            if (data.size > MANIFEST_LIMIT || crypto.digest(data) != name.sha256) fail(ShelfError.InvalidManifest)
            val file = Fields(Json.read(data).jsonObject())
            val version = file.number("version")
            val created = instant(file.text("created_at"))
            val artifacts = file.list("artifacts").map { Fields(it.jsonObject()) }
            if (version !in 1L..2L || file.text("title_id") != titleID || artifacts.map { it.text("kind") } !in KINDS ||
                (version == 1L && data.size > LEGACY_LIMIT)
            ) fail(ShelfError.InvalidManifest)
            var app: ShelfMacBuild? = null
            for (artifact in artifacts) {
                val kind = artifact.text("kind")
                val bytes = artifact.number("unpacked_size")
                val digest = artifact.text("inventory_sha256")
                val options = artifact.fields("options")
                val published = artifact.optionalText("published_at")?.let { instant(it) }
                if (bytes < 0 || !ShelfNames.isHex(digest, 64)) fail(ShelfError.InvalidManifest)
                val revision = artifact.optionalNumber("revision")
                if (revision != null && (revision <= 0 || revision > name.stamp || published != Instant.ofEpochSecond(revision / 1000))) fail(ShelfError.InvalidManifest)
                val tree = artifact.optionalFields("files")
                if (tree != null) checkTree(tree, artifact, version, kind, digest, bytes, titleID, crypto)
                else if ((artifact.optionalNumber("size") ?: 0) <= 0 || !ShelfNames.isHex(artifact.optionalText("sha256"), 64) ||
                    !ShelfNames.isHex(artifact.optionalText("md5"), 32)
                ) fail(ShelfError.InvalidManifest)
                if (kind == "app") {
                    app = ShelfMacBuild(
                        titleID, file.optionalText("game_name")?.let { ShelfNames.displayName(it, titleID) },
                        options.optionalText("CFBundleShortVersionString"), artifact.optionalText("engine_commit"), bytes,
                        revision ?: (published ?: created).toEpochMilli(),
                    )
                }
            }
            return app
        }

        private fun checkTree(tree: Fields, artifact: Fields, version: Long, kind: String, digest: String, bytes: Long, titleID: String, crypto: ShelfCrypto) {
            val parts = tree.text("folder").split("/")
            val entries = tree.list("entries").map { Fields(it.jsonObject()) }
            var total = 0L
            val text = entries.joinToString(",", "[", "]") {
                val size = it.number("size")
                val md5 = it.text("md5")
                if (size < 0 || size > Long.MAX_VALUE - total || !ShelfNames.isHex(md5, 32)) fail(ShelfError.InvalidManifest)
                total += size
                "{\"md5\":\"$md5\",\"path\":${ShelfNames.quoted(it.text("path"))},\"size\":$size}"
            }
            if (version != 2L || artifact.has("size") || artifact.has("sha256") || artifact.has("md5") ||
                artifact.number("entry_count") != entries.size.toLong() || parts.size != (if (kind == "app") 4 else 3) ||
                !parts.all { ShelfNames.isPlain(it) } || !parts[0].endsWith(" [$titleID]") || parts[1] != kind || parts[2] != digest ||
                crypto.digest(text.toByteArray()) != digest || total != bytes
            ) fail(ShelfError.InvalidManifest)
        }

        private fun instant(text: String): Instant = try {
            Instant.parse(text)
        } catch (_: DateTimeParseException) {
            fail(ShelfError.InvalidManifest)
        }
    }
}

/** Typed reading of a manifest's object: anything missing or of another type makes it invalid. */
internal class Fields(map: Map<String, Any?>?) {
    private val map = map ?: fail(ShelfError.InvalidManifest)

    fun has(key: String): Boolean = map[key] != null
    fun text(key: String): String = map[key] as? String ?: fail(ShelfError.InvalidManifest)
    fun number(key: String): Long = map[key] as? Long ?: fail(ShelfError.InvalidManifest)
    fun list(key: String): List<Any?> = map[key] as? List<Any?> ?: fail(ShelfError.InvalidManifest)
    fun fields(key: String): Fields = Fields(map[key].jsonObject())
    fun optionalText(key: String): String? = if (has(key)) text(key) else null
    fun optionalNumber(key: String): Long? = if (has(key)) number(key) else null
    fun optionalFields(key: String): Fields? = if (has(key)) fields(key) else null
}
