package io.github.sofianbll.oortnx.ui

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource

/** Words on screen: a resource read in the language of the moment, or text that is already words (a game's name). */
sealed interface Label {
    class Res(@param:StringRes val id: Int, vararg val args: Any) : Label
    class Raw(val text: String) : Label
    class Join(val parts: List<Label>, val lines: Boolean = false) : Label

    /** The same words in several languages, from a file rather than the resources. */
    class Words(val words: Map<String, String>) : Label
}

@Composable
fun Label.text(): String = when (this) {
    is Label.Raw -> text
    is Label.Words -> LocalConfiguration.current.locales[0].let { words[it.toLanguageTag()] ?: words[it.language] ?: words["en"].orEmpty() }
    is Label.Join -> parts.map { it.text() }.joinToString(if (lines) "\n" else "  ·  ")
    is Label.Res -> if (args.isEmpty()) stringResource(id) else stringResource(id, *args.map { if (it is Label) it.text() else it }.toTypedArray())
}

/** What a line does. */
sealed interface Kind {
    data object Info : Kind
    class Press(val run: () -> Unit) : Kind
    class Open(val route: Route) : Kind
    /** A page of the web, in the player's browser. */
    class Link(val url: String) : Kind
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
    @param:DrawableRes val picture: Int? = null,
    val danger: Boolean = false,
    val kind: Kind = Kind.Info,
)

class RowSection(val title: Label? = null, val footer: Label? = null, val rows: List<RowItem>)

enum class Section { Home, Library, Controllers, Settings }

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
}

/** The texts packaged with the app (assets/licences). */
enum class LicenceText(val file: String, val title: String) {
    Oort("oort-nx.txt", "Oort NX"),
    Notices("notices.txt", "NOTICE"),
    Apache("apache-2.0.txt", "Apache License 2.0"),
}
