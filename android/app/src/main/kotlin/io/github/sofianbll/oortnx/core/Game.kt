package io.github.sofianbll.oortnx.core

/** A game installed on this device by nx2android: one APK per game, package `org.nx2a.*`. */
data class Game(
    val packageName: String,
    val title: String,
    val versionName: String,
    val versionCode: Long,
    /** Android's own launch intent target; null when the package has no launcher activity. */
    val activity: String?,
)

/** How nx2android names the packages it makes (porter/saves.py PREFIX, mkapk.py `--package`). */
object Nx2Android {
    const val PREFIX = "org.nx2a."

    fun isGamePackage(name: String): Boolean = name.startsWith(PREFIX) && name.length > PREFIX.length

    /** `org.nx2a.t0100000011d90000` carries its title ID; the others (`org.nx2a.supermarioodyssey`) do not. */
    fun titleId(name: String): String? {
        val tail = name.removePrefix(PREFIX)
        return if (Regex("t[0-9a-f]{16}").matches(tail)) tail.substring(1).uppercase() else null
    }
}
