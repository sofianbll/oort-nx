package io.github.sofianbll.oortnx.shelf

import java.text.Normalizer
import java.util.Locale

/**
 * The rules every name read from a source goes through. They are the Mac's (CloudDriveFolders.validName, titleID(in:),
 * CloudArtifactFiles.validate), tightened for a folder somebody else may have written into.
 */
object ShelfNames {
    private const val LINK_SUFFIX = ".rclonelink"
    private val KEY_NAMES = setOf("prod.keys", "title.keys", "dev.keys", "keys.txt")

    /** A manifest's name: its publication time in milliseconds and its content's SHA-256. */
    data class Stamped(val stamp: Long, val sha256: String) : Comparable<Stamped> {
        override fun compareTo(other: Stamped): Int = compareValuesBy(this, other, { it.stamp }, { it.sha256 })
    }

    fun isTitleID(text: String): Boolean = text.length == 16 && text.all { it in '0'..'9' || it in 'A'..'F' }

    /** `Name [0100…]` or `0100…`, capitals only. */
    fun titleID(folder: String): String? {
        if (!isPlain(folder) || '/' in folder) return null
        val title = if (folder.endsWith("]")) folder.dropLast(1).takeLast(16) else folder
        return title.takeIf { isTitleID(it) && (folder == it || folder.endsWith(" [$it]")) }
    }

    /** What to show for a game folder. A name is text from outside: it never carries a line break or a direction mark. */
    fun displayName(text: String, titleID: String): String {
        val name = text.removeSuffix(" [$titleID]")
        val clean = buildString { name.codePoints().filter { !isControl(it) }.forEach { appendCodePoint(it) } }.trim { it.isWhitespace() }
        if (clean.isEmpty()) return titleID
        return buildString { clean.codePoints().limit(120).forEach { appendCodePoint(it) } }
    }

    /** Two names a disk could take for the same one. */
    fun folded(name: String): String = Normalizer.normalize(name, Normalizer.Form.NFC).lowercase(Locale.ROOT)

    /** A relative path that stays inside its folder on every system, with no name a system gives a meaning to. */
    fun isSafePath(path: String): Boolean {
        if (!isPlain(path) || path.toByteArray().size !in 1..1024) return false
        val parts = path.split("/")
        if (parts.size > 16) return false
        val safe = parts.all { part ->
            val lower = part.lowercase(Locale.ROOT)
            part.isNotEmpty() && part.toByteArray().size <= 255 && !part.startsWith(".") && !part.endsWith(".") && !part.endsWith(" ") &&
                !part.startsWith(" ") && lower !in KEY_NAMES && !lower.endsWith(LINK_SUFFIX)
        }
        // Saves never travel with a build.
        return safe && !parts[0].lowercase(Locale.ROOT).startsWith("save")
    }

    /** Letters a folder tree can hold everywhere: no backslash, colon, control or direction mark, no `.` or `..` part. */
    fun isPlain(path: String): Boolean = path.isNotBlank() && '\\' !in path && ':' !in path &&
        path.codePoints().noneMatch { isControl(it) } && path.split("/").none { it == "." || it == ".." }

    private fun isControl(c: Int): Boolean = c < 0x20 || c in 0x7F until 0xA0 || c in 0x200B..0x200F || c in 0x2028..0x202E ||
        c in 0x2060..0x206F || c == 0xFEFF

    fun isHex(text: String?, count: Int): Boolean = text != null && text.length == count && text.all { it in '0'..'9' || it in 'a'..'f' }

    fun manifestName(name: String): Stamped? {
        if (!name.endsWith(".json")) return null
        val parts = name.removeSuffix(".json").split("-")
        if (parts.size != 2 || parts[0].length != 16 || !parts[0].all { it in '0'..'9' } || !isHex(parts[1], 64)) return null
        return Stamped(parts[0].toLong(), parts[1])
    }

    /** One JSON string, escaped the way the Mac's encoder does it, so both sides hash the same bytes. */
    fun quoted(text: String): String = "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\""

    /** Dotted numbers, missing parts count as zero. Null when it is not a version. */
    fun compareVersions(a: String, b: String): Int? {
        fun parts(text: String): List<Int>? {
            val items = text.split(".")
            if (items.size !in 1..4 || items.any { it.isEmpty() || it.length > 6 || !it.all { c -> c in '0'..'9' } }) return null
            return items.map { it.toInt() }
        }
        val left = parts(a) ?: return null
        val right = parts(b) ?: return null
        for (i in 0 until 4) {
            val order = (left.getOrElse(i) { 0 }).compareTo(right.getOrElse(i) { 0 })
            if (order != 0) return order
        }
        return 0
    }
}

/** The only child with this exact name and kind. A name that a disk could confuse with another one is refused. */
internal fun List<ShelfNode>.only(name: String, kind: ShelfNode.Kind): ShelfNode? {
    val matches = filter { ShelfNames.folded(it.name) == ShelfNames.folded(name) }
    val match = matches.firstOrNull() ?: return null
    if (matches.size != 1 || match.name != name || match.kind != kind) fail(ShelfError.Ambiguous)
    return match
}
