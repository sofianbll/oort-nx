package io.github.sofianbll.oortnx.ui

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource

/** Words on screen: a resource read in the language of the moment, or text that is already words (a game's name). */
sealed interface Label {
    class Res(@param:StringRes val id: Int, vararg val args: Any) : Label
    class Raw(val text: String) : Label
    class Join(val parts: List<Label>) : Label
}

@Composable
fun Label.text(): String = when (this) {
    is Label.Raw -> text
    is Label.Join -> parts.map { it.text() }.joinToString("  ·  ")
    is Label.Res -> if (args.isEmpty()) stringResource(id) else stringResource(id, *args.map { if (it is Label) it.text() else it }.toTypedArray())
}

/** What a line does. */
sealed interface Kind {
    data object Info : Kind
    class Press(val run: () -> Unit) : Kind
    class Open(val route: Route) : Kind
    class Toggle(val on: Boolean, val set: (Boolean) -> Unit) : Kind
    class Pick(val on: Boolean, val run: () -> Unit) : Kind
}

/** One line of a list: what it says and what it does. Every list of the app is made of these, for the finger and the controller alike. */
class RowItem(
    val id: String,
    val title: Label,
    val value: Label? = null,
    val note: Label? = null,
    val glyph: Glyph? = null,
    val danger: Boolean = false,
    val kind: Kind = Kind.Info,
)

class RowSection(val title: Label? = null, val footer: Label? = null, val rows: List<RowItem>)

enum class Section { Home, Library, Controllers, Settings }

/** The keys above the library's covers, in their order. */
enum class LibraryKey { All, Favorites, Search, Sort }

/** A page opened over a section. */
sealed interface Route {
    data class GamePage(val packageName: String) : Route
    data object PadTest : Route
    data object Sounds : Route
    data object Buttons : Route
    data object Cloud : Route
    data object WhichGames : Route
    data object Thanks : Route
    data class Licence(val text: LicenceText) : Route

    /** A name that says which page it is, to keep the focus of each. */
    val key: String get() = toString()

    /** The page as a word Android can keep while the app is away; [routeOf] reads it back. */
    val saved: String
        get() = when (this) {
            is GamePage -> "game:$packageName"
            is Licence -> "licence:${text.name}"
            PadTest -> "padtest"
            Sounds -> "sounds"
            Buttons -> "buttons"
            Cloud -> "cloud"
            WhichGames -> "which"
            Thanks -> "thanks"
        }
}

/** Null for a word this version does not know. */
fun routeOf(saved: String): Route? {
    val rest = saved.substringAfter(':', "")
    return when (saved.substringBefore(':')) {
        "game" -> Route.GamePage(rest)
        "licence" -> LicenceText.entries.firstOrNull { it.name == rest }?.let { Route.Licence(it) }
        "padtest" -> Route.PadTest
        "sounds" -> Route.Sounds
        "buttons" -> Route.Buttons
        "cloud" -> Route.Cloud
        "which" -> Route.WhichGames
        "thanks" -> Route.Thanks
        else -> null
    }
}

/** A page of words with nothing to choose: up and down scroll it. */
val Route?.isText: Boolean get() = this is Route.Licence || this == Route.WhichGames

/** The texts packaged with the app (assets/licences). */
enum class LicenceText(val file: String, val title: String) {
    Oort("oort-nx.txt", "Oort NX"),
    Notices("notices.txt", "NOTICE"),
    Apache("apache-2.0.txt", "Apache License 2.0"),
}
