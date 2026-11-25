package io.github.sofianbll.oortnx.cloud

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.DocumentsContract
import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfBuild
import io.github.sofianbll.oortnx.shelf.ShelfCrypto
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfNames
import io.github.sofianbll.oortnx.shelf.ShelfStore
import io.github.sofianbll.oortnx.shelf.fail
import io.github.sofianbll.oortnx.shelf.hex
import io.github.sofianbll.oortnx.shelf.jsonObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest

/** What was installed from here: the build, its package, and the files it put in the shared folder. */
internal data class Receipt(val digest: String, val version: String, val packageName: String, val code: Long, val files: List<String>, val present: Boolean)

/** Checks an APK before Android is asked to install it, and puts a game's data where the player chose. Saves and Drive are never touched. */
internal class CloudInstalls(private val context: Context, private val store: ShelfStore, private val receipts: File) {
    private val prefs get() = context.getSharedPreferences("cloud", Context.MODE_PRIVATE)

    /** The folder the player chose for the games' data, kept between two runs by Android itself. */
    var folder: Uri?
        get() = prefs.getString("folder", null)?.let(Uri::parse)?.takeIf { uri -> context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isWritePermission } }
        set(value) { prefs.edit().putString("folder", value?.toString()).commit() }

    fun all(): Map<String, Receipt> = (receipts.listFiles() ?: emptyArray()).filter { ShelfNames.isTitleID(it.nameWithoutExtension) }.mapNotNull { file ->
        val map = try { Json.read(file.readBytes()).jsonObject() } catch (_: IOException) { null } ?: return@mapNotNull null
        val name = map["package"] as? String ?: return@mapNotNull null
        val code = map["code"] as? Long ?: return@mapNotNull null
        val here = info(name)
        file.nameWithoutExtension to Receipt(map["digest"] as? String ?: "", map["version"] as? String ?: "", name, code,
            (map["files"] as? List<*>).orEmpty().mapNotNull { it as? String }, here != null && here.longVersionCode == code)
    }.toMap()

    fun digests(): Map<String, String> = all().filterValues { it.present }.mapValues { it.value.digest }

    fun info(name: String): PackageInfo? = try { context.packageManager.getPackageInfo(name, 0) } catch (_: PackageManager.NameNotFoundException) { null }

    fun apk(build: ShelfBuild) = File(store.visible(build), build.packagePath)
    fun data(build: ShelfBuild) = build.entries.filter { it.path != build.packagePath }

    /** Android checks the signature again when it installs; here the player is told before being asked anything. */
    @Suppress("DEPRECATION")
    fun check(build: ShelfBuild) {
        val file = apk(build)
        val entry = build.entries.first { it.path == build.packagePath }
        if (!file.isFile || digest(file) != entry.sha256) fail(ShelfError.WrongDigest)
        val info = context.packageManager.getPackageArchiveInfo(file.path, PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES) ?: fail(ShelfError.InvalidManifest)
        // Android 10 gives an APK's signer only under its older name.
        val signers = (info.signingInfo?.apkContentsSigners ?: info.signatures).orEmpty().map { ShelfCrypto.sha256().digest(it.toByteArray()).hex() }
        refusal(build, info.packageName, info.longVersionCode, signers)?.let { fail(it) }
        for (one in data(build)) if (!isDataPath(one.path)) fail(ShelfError.UnsafeName)
    }

    /** Beside the game's own files, never in them: `<folder>/<title>/…`, one file at a time, whole or not at all. */
    fun place(build: ShelfBuild) {
        val entries = data(build)
        if (entries.isEmpty()) return
        val tree = folder ?: fail(ShelfError.LocalFile)
        val top = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val known = HashMap<String, Uri>()
        fun folder(path: String): Uri = known.getOrPut(path) {
            if (path.isEmpty()) top else {
                val parent = folder(path.substringBeforeLast('/', ""))
                val name = path.substringAfterLast('/')
                child(tree, parent, name)?.first ?: create(parent, DocumentsContract.Document.MIME_TYPE_DIR, name)
            }
        }
        for (entry in entries) {
            val name = entry.path.substringAfterLast('/')
            val parent = folder((build.titleID + "/" + entry.path.removePrefix("data/")).substringBeforeLast('/'))
            val source = File(store.visible(build), entry.path)
            val old = child(tree, parent, name)
            if (!source.isFile) {
                // Put there by a try that was stopped.
                if (old?.second == entry.size) continue
                fail(ShelfError.FilesMissing)
            }
            try {
                child(tree, parent, "$name.oort-part")?.let { DocumentsContract.deleteDocument(context.contentResolver, it.first) }
                val part = create(parent, "application/octet-stream", "$name.oort-part")
                val hash = ShelfCrypto.sha256()
                context.contentResolver.openOutputStream(part, "w")!!.use { out ->
                    source.inputStream().use { input ->
                        val buffer = ByteArray(1 shl 20)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            hash.update(buffer, 0, count)
                            out.write(buffer, 0, count)
                        }
                    }
                }
                if (hash.digest().hex() != entry.sha256) {
                    DocumentsContract.deleteDocument(context.contentResolver, part)
                    fail(ShelfError.WrongDigest)
                }
                old?.let { DocumentsContract.deleteDocument(context.contentResolver, it.first) }
                DocumentsContract.renameDocument(context.contentResolver, part, name)
            } catch (failure: IOException) {
                fail(if (failure.message.orEmpty().contains("ENOSPC")) ShelfError.NoSpace(entry.size) else ShelfError.LocalFile)
            }
            source.delete()
        }
    }

    /** The game and its data are in place: what the last build left and this one does not have goes, then the download. */
    fun finish(build: ShelfBuild) {
        val files = data(build).map { it.path.removePrefix("data/") }
        all()[build.titleID]?.let { old -> remove(build.titleID, old.files - files.toSet()) }
        receipts.mkdirs()
        File(receipts, build.titleID + ".json").writeText(CloudQueue.write(mapOf(
            "digest" to build.digest, "version" to build.gameVersion, "package" to build.packageID, "code" to build.packageVersion, "files" to files)))
        File(store.root, build.titleID).deleteRecursively()
    }

    /** After the player uninstalled the game: the data it read from the shared folder. */
    fun clean(id: String) {
        val receipt = all()[id] ?: return
        if (receipt.present) return
        remove(id, receipt.files)
        File(receipts, "$id.json").delete()
    }

    private fun remove(id: String, files: List<String>) {
        val tree = folder ?: return
        val top = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        val mine = child(tree, top, id)?.first ?: return
        for (path in files.filter { isDataPath("data/$it") }) {
            var at: Uri? = mine
            for (piece in path.split("/")) at = at?.let { child(tree, it, piece)?.first }
            try { at?.let { DocumentsContract.deleteDocument(context.contentResolver, it) } } catch (_: Exception) { /* Already gone. */ }
        }
        if (files.isNotEmpty() && isEmpty(tree, mine)) try { DocumentsContract.deleteDocument(context.contentResolver, mine) } catch (_: Exception) { /* Already gone. */ }
    }

    private fun isEmpty(tree: Uri, folder: Uri): Boolean = list(tree, folder).all { (uri, _, size) -> size == null && isEmpty(tree, uri) }

    private fun child(tree: Uri, parent: Uri, name: String): Pair<Uri, Long?>? = list(tree, parent).firstOrNull { it.second == name }?.let { it.first to it.third }

    /** Address, name, and size of a file (null: a folder). */
    private fun list(tree: Uri, parent: Uri): List<Triple<Uri, String, Long?>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE)
        val found = mutableListOf<Triple<Uri, String, Long?>>()
        context.contentResolver.query(children, columns, null, null, null)?.use { c ->
            while (c.moveToNext()) found += Triple(DocumentsContract.buildDocumentUriUsingTree(tree, c.getString(0)), c.getString(1),
                if (c.getString(3) == DocumentsContract.Document.MIME_TYPE_DIR) null else c.getLong(2))
        }
        return found
    }

    private fun create(parent: Uri, type: String, name: String): Uri =
        try { DocumentsContract.createDocument(context.contentResolver, parent, type, name) } catch (_: Exception) { null } ?: fail(ShelfError.LocalFile)

    private fun digest(file: File): String {
        val hash: MessageDigest = ShelfCrypto.sha256()
        file.inputStream().use { input ->
            val buffer = ByteArray(1 shl 20)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                hash.update(buffer, 0, count)
            }
        }
        return hash.digest().hex()
    }

    companion object {
        /** The signed manifest names the package, its version and its signer: the APK must be that one. */
        fun refusal(build: ShelfBuild, name: String?, code: Long, signers: List<String>): ShelfError? = when {
            name != build.packageID || code != build.packageVersion -> ShelfError.WrongDigest
            signers != listOf(build.packageSigner) -> ShelfError.Unsigned
            else -> null
        }

        fun isDataPath(path: String): Boolean = path.startsWith("data/") && ShelfNames.isSafePath(path) && !path.removePrefix("data/").lowercase().startsWith("save")
    }
}
