package io.github.sofianbll.oortnx.ui

import android.app.Activity
import android.content.Context
import android.os.Bundle
import android.view.KeyEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.ConnectedPad
import io.github.sofianbll.oortnx.core.Covers
import io.github.sofianbll.oortnx.core.Dir
import io.github.sofianbll.oortnx.core.Game
import io.github.sofianbll.oortnx.core.GameLauncher
import io.github.sofianbll.oortnx.core.GameScanner
import io.github.sofianbll.oortnx.core.LastStart
import io.github.sofianbll.oortnx.core.Nav
import io.github.sofianbll.oortnx.core.Nx2Android
import io.github.sofianbll.oortnx.core.OortSynth
import io.github.sofianbll.oortnx.core.PadFamily
import io.github.sofianbll.oortnx.core.PadMonitor
import io.github.sofianbll.oortnx.core.Prefs
import io.github.sofianbll.oortnx.core.SoundEvent
import io.github.sofianbll.oortnx.core.SoundPlayer
import io.github.sofianbll.oortnx.core.gridMove
import io.github.sofianbll.oortnx.core.lastStartedFirst
import io.github.sofianbll.oortnx.core.matches
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import kotlin.concurrent.thread

/** What the controller is on, in À la une. */
enum class HomeTarget { Cover, Play, Page, Android }

/** What is on screen and where the focus is. Kept by hand, with no framework: it is small. */
class AppState(
    private val context: Context,
    /** The activity itself, for what must open on top of it. */
    private val screen: Activity,
    val prefs: Prefs,
    private val soundPlayer: SoundPlayer,
    /** A debuggable build started with `--ez demo true` shows made-up entries, to look at the screens without a game. */
    private val demo: Boolean,
    private val versionName: String,
) {
    var section by mutableStateOf(Section.Home)
        private set
    private var stacks by mutableStateOf<Map<Section, List<Route>>>(emptyMap())

    /** The page over the section, if any. */
    val route: Route? get() = stacks[section]?.lastOrNull()

    private var found by mutableStateOf<List<Game>>(emptyList())
    var icons by mutableStateOf<Map<String, ImageBitmap>>(emptyMap())
        private set
    var scanned by mutableStateOf(false)
        private set

    /** The last started first: À la une. */
    val recent: List<Game> get() = lastStartedFirst(found, prefs.started)
    /** What the library shows: every game or the favourites, in the chosen order, narrowed by the search. */
    val library: List<Game> get() = (if (prefs.byName) found else recent)
        .filter { (!onlyFavorites || it.packageName in prefs.favorites) && matches(it.title, query) }
    var onlyFavorites by mutableStateOf(false)
        private set
    var searching by mutableStateOf(false)
        private set
    var query by mutableStateOf("")
        private set

    /** The key above the covers that the controller or the keyboard is on; null while it is on a cover. */
    var libraryKey by mutableStateOf<LibraryKey?>(null)
        private set

    /** True while the search field has the focus: the keys typed there are its own. */
    var typing by mutableStateOf(false)

    /** Each change asks the search field to take the focus, or to give it back. */
    var fieldAsked by mutableIntStateOf(0)
        private set
    var fieldLeft by mutableIntStateOf(0)
        private set
    val count: Int get() = found.size

    /** True once a pad or a keyboard moved the focus; a touch puts it back to false. */
    var padMode by mutableStateOf(false)
    private var selectedPackage by mutableStateOf<String?>(null)
    val selected: Game? get() = recent.let { all -> all.firstOrNull { it.packageName == selectedPackage } ?: all.firstOrNull() }
    var homeTarget by mutableStateOf(HomeTarget.Cover)
        private set
    var libraryFocus by mutableIntStateOf(0)
        private set
    var columns by mutableIntStateOf(2)
    private var rowFocus by mutableStateOf<Map<String, String>>(emptyMap())
    private var menuPackage by mutableStateOf<String?>(null)

    /** The game whose options are open over the page. */
    val menuGame: Game? get() = menuPackage?.let { game(it) }

    /** Up and down on a page of text, for the page to follow. */
    var textSteps by mutableIntStateOf(0)
        private set
    var pads by mutableStateOf<List<ConnectedPad>>(emptyList())

    /** The marks of the controller used last: what the hints show. */
    var family by mutableStateOf(PadFamily())

    /** True when the last key came from a keyboard: the hints show its keys. */
    var keyboard by mutableStateOf(false)

    /** What is written on that key: of the keyboard, else of the controller in hand. */
    fun keyName(key: HintKey): String = if (keyboard) when (key) {
        HintKey.Confirm -> context.getString(R.string.key_enter)
        HintKey.Back -> context.getString(R.string.key_escape)
        HintKey.Details -> "Ctrl D"
        HintKey.Search -> "Ctrl F"
        HintKey.Options -> "Ctrl O"
        HintKey.Tabs -> "Q E"
        HintKey.Sort -> "F3"
    } else when (key) {
        HintKey.Confirm -> family.mark(if (prefs.swapAB) KeyEvent.KEYCODE_BUTTON_B else KeyEvent.KEYCODE_BUTTON_A)
        HintKey.Back -> family.mark(if (prefs.swapAB) KeyEvent.KEYCODE_BUTTON_A else KeyEvent.KEYCODE_BUTTON_B)
        HintKey.Details -> family.mark(KeyEvent.KEYCODE_BUTTON_X)
        HintKey.Search -> family.mark(KeyEvent.KEYCODE_BUTTON_Y)
        HintKey.Options -> family.mark(KeyEvent.KEYCODE_BUTTON_START)
        HintKey.Tabs -> family.mark(KeyEvent.KEYCODE_BUTTON_L1) + " " + family.mark(KeyEvent.KEYCODE_BUTTON_R1)
        HintKey.Sort -> family.mark(KeyEvent.KEYCODE_BUTTON_THUMBR)
    }
    val pad = PadMonitor()
    var message by mutableStateOf<String?>(null)
    private var step = 0

    fun game(packageName: String): Game? = found.firstOrNull { it.packageName == packageName }

    /** Reads the installed games again. [say]: the player asked, so the answer is said. */
    fun rescan(say: Boolean = false) {
        thread(name = "oort-scan", isDaemon = true) {
            val games = if (demo) DEMO_GAMES else GameScanner.scan(context)
            val pictures = games.mapNotNull { game -> Covers.of(context, game)?.let { game.packageName to it } }.toMap()
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                take(games, pictures)
                if (say) message = context.getString(R.string.library_count, games.size)
            }
        }
    }

    private fun take(games: List<Game>, pictures: Map<String, ImageBitmap>) {
        found = games
        icons = pictures
        libraryFocus = libraryFocus.coerceIn(0, (library.size - 1).coerceAtLeast(0))
        // The page of a game that went away closes by itself.
        val gone = { r: Route -> r is Route.GamePage && games.none { it.packageName == r.packageName } }
        if (stacks.values.any { it.any(gone) }) stacks = stacks.mapValues { (_, pages) -> pages.takeWhile { !gone(it) } }
        if (menuPackage != null && menuGame == null) menuPackage = null
        scanned = true
    }

    // ---- what Android keeps while the app is away ----------------------------------------------------------

    /**
     * Android rebuilds the activity for a few changes (bold text among them) and ends the app when it needs memory:
     * the place the player was on comes back with it.
     */
    fun save(into: Bundle) {
        into.putString("section", section.name)
        for ((where, pages) in stacks) into.putStringArray("pages:${where.name}", pages.map { it.saved }.toTypedArray())
        into.putString("selected", selectedPackage)
        into.putInt("focus", libraryFocus)
        into.putBoolean("favorites", onlyFavorites)
        into.putBoolean("searching", searching)
        into.putString("query", query)
    }

    fun restore(from: Bundle) {
        section = Section.entries.firstOrNull { it.name == from.getString("section") } ?: Section.Home
        stacks = Section.entries.mapNotNull { where -> from.getStringArray("pages:${where.name}")?.let { saved -> where to saved.mapNotNull(::routeOf) } }.toMap()
        selectedPackage = from.getString("selected")
        libraryFocus = from.getInt("focus")
        onlyFavorites = from.getBoolean("favorites")
        searching = from.getBoolean("searching")
        query = from.getString("query").orEmpty()
    }

    // ---- moving about -------------------------------------------------------------------------------------

    /** The bar and the rail. The section already open goes back to its first page. */
    fun goTo(next: Section) {
        libraryKey = null
        if (next == section && route == null) return
        if (next == section) stacks = stacks - section
        section = next
        sound(SoundEvent.Open)
    }

    fun open(route: Route) {
        stacks = stacks + (section to (stacks[section].orEmpty() + route))
        rowFocus = rowFocus - route.key
        sound(SoundEvent.Open)
    }

    /** The system's Back (gesture or key). False when there is nothing left to go back to: Android then leaves the app. */
    fun onBack(): Boolean {
        if (!canGoBack) return false
        if (menuGame != null) { closeMenu(); sound(SoundEvent.Back); return true }
        if (searchOnScreen) { closeSearch(); sound(SoundEvent.Back); return true }
        if (route != null) stacks = stacks + (section to stacks[section].orEmpty().dropLast(1))
        else section = Section.Home
        sound(SoundEvent.Back)
        return true
    }

    val canGoBack: Boolean get() = menuGame != null || route != null || section != Section.Home
    private val searchOnScreen: Boolean get() = searching && route == null && section == Section.Library

    fun select(game: Game) {
        if (game.packageName == selected?.packageName) return
        selectedPackage = game.packageName
        sound(SoundEvent.Move, step++)
    }

    fun openGame(game: Game) {
        selectedPackage = game.packageName
        libraryFocus = library.indexOf(game).coerceAtLeast(0)
        open(Route.GamePage(game.packageName))
    }

    /** A game's options: by + on the controller, a long press under the finger. */
    fun openMenu(game: Game) {
        selectedPackage = game.packageName
        if (section == Section.Library && route == null) libraryFocus = library.indexOf(game).coerceAtLeast(0)
        rowFocus = rowFocus - MENU
        menuPackage = game.packageName
        sound(SoundEvent.Open)
    }

    fun closeMenu() { menuPackage = null }

    /** The game the player is on: the one whose options + opens. None on the pages that show no game. */
    private fun currentGame(): Game? = when (val page = route) {
        is Route.GamePage -> game(page.packageName)
        null -> when (section) {
            Section.Home -> selected
            Section.Library -> if (libraryKey == null) library.getOrNull(libraryFocus) else null
            else -> null
        }
        else -> null
    }

    // ---- the library's search and favourites ------------------------------------------------------------------

    fun filter(favoritesOnly: Boolean) {
        if (favoritesOnly == onlyFavorites) return
        onlyFavorites = favoritesOnly
        libraryFocus = 0
        sound(SoundEvent.Select)
    }

    /** Y, Ctrl+F or the magnifier: the library, with the field ready to type in. */
    fun search() {
        stacks = stacks - Section.Library
        section = Section.Library
        libraryKey = null
        searching = true
        libraryFocus = 0
        fieldAsked++
        sound(SoundEvent.Open)
    }

    fun type(text: String) { query = text; libraryFocus = 0 }

    fun closeSearch() { searching = false; query = ""; typing = false; libraryFocus = 0 }

    /** From the field to what it found: the keyboard leaves, the first cover takes the ring. */
    fun leaveField() {
        fieldLeft++
        typing = false
        libraryKey = if (library.isEmpty()) LibraryKey.Search else null
        libraryFocus = 0
    }

    fun toggleFavorite(game: Game, say: Boolean = true) {
        val here = library.getOrNull(libraryFocus)
        prefs.saveFavorite(game.packageName, game.packageName !in prefs.favorites)
        // The ring stays on its game; one that left the favourites leaves it to its neighbour.
        libraryFocus = library.indexOf(here).takeIf { it >= 0 } ?: libraryFocus.coerceIn(0, (library.size - 1).coerceAtLeast(0))
        if (say) sound(SoundEvent.Select)
    }

    // ---- what a button does -------------------------------------------------------------------------------

    fun onNav(nav: Nav) {
        padMode = true
        if (menuGame != null) {
            when (nav) {
                Nav.Back, Nav.Options -> onBack()
                Nav.Forward, Nav.Backward -> step(nav == Nav.Forward)
                Nav.Up, Nav.Down, Nav.Confirm, Nav.First, Nav.Last -> listNav(nav)
                else -> sound(SoundEvent.Deny)
            }
            return
        }
        // A controller picked up while the field is typed in: Android's keyboard cannot be steered by it, so the first
        // press leaves the field for what it found.
        if (typing && !keyboard && nav != Nav.Back && nav != Nav.Search && nav != Nav.Next && nav != Nav.Previous) return leaveField()
        when (nav) {
            Nav.Next -> return cycle(1)
            Nav.Previous -> return cycle(-1)
            Nav.Search -> return search()
            Nav.Options -> { currentGame()?.let { openMenu(it) } ?: goTo(Section.Settings); return }
            Nav.Settings -> return goTo(Section.Settings)
            Nav.Forward, Nav.Backward -> return step(nav == Nav.Forward)
            Nav.Back -> { if (!onBack()) sound(SoundEvent.Deny); return }
            else -> Unit
        }
        val page = route
        when {
            page.isText -> textNav(nav)
            page != null -> listNav(nav)
            section == Section.Home -> homeNav(nav)
            section == Section.Library -> libraryNav(nav)
            else -> listNav(nav)
        }
    }

    /** Tab and Shift+Tab: the next and the previous place of what is on screen, round and round, with the same ring. */
    private fun step(forward: Boolean) {
        val by = if (forward) 1 else -1
        val page = route
        fun <T> next(all: List<T>, here: T): T = all[(all.indexOf(here) + by + all.size) % all.size]
        when {
            menuGame == null && page.isText -> textNav(if (forward) Nav.Down else Nav.Up)
            menuGame == null && page == null && section == Section.Home -> if (selected != null) moveHome(next(HomeTarget.entries, homeTarget))
            menuGame == null && page == null && section == Section.Library -> {
                // The keys above the covers, then the covers.
                val keys = LibraryKey.entries
                val places = keys.size + library.size
                val here = libraryKey?.ordinal ?: (keys.size + libraryFocus.coerceIn(0, (library.size - 1).coerceAtLeast(0)))
                val to = (here + by + places) % places
                libraryKey = keys.getOrNull(to)
                if (libraryKey == null) libraryFocus = to - keys.size
                sound(SoundEvent.Move, step++)
            }
            else -> focusedRow()?.let { rowFocus = rowFocus + (pageKey to next(rowIds(), it)); sound(SoundEvent.Move, step++) }
        }
    }

    private fun cycle(by: Int) {
        val all = Section.entries
        goTo(all[(section.ordinal + by + all.size) % all.size])
    }

    private fun homeNav(nav: Nav) {
        val game = selected
        if (game == null) { if (nav == Nav.Confirm) rescan(); return }
        val all = recent
        val here = all.indexOf(game)
        when (nav) {
            Nav.Left, Nav.Right -> {
                val by = if (nav == Nav.Right) 1 else -1
                if (homeTarget == HomeTarget.Cover) {
                    all.getOrNull(here + by)?.let { select(it) } ?: sound(SoundEvent.Deny)
                } else {
                    val next = homeTarget.ordinal + by
                    if (next in HomeTarget.Play.ordinal..HomeTarget.Android.ordinal) moveHome(HomeTarget.entries[next]) else sound(SoundEvent.Deny)
                }
            }
            Nav.Down -> if (homeTarget == HomeTarget.Cover) moveHome(HomeTarget.Play) else sound(SoundEvent.Deny)
            Nav.Up -> if (homeTarget != HomeTarget.Cover) moveHome(HomeTarget.Cover) else sound(SoundEvent.Deny)
            Nav.Confirm -> when (homeTarget) {
                HomeTarget.Cover, HomeTarget.Play -> play(game)
                HomeTarget.Page -> openGame(game)
                HomeTarget.Android -> androidPage(game)
            }
            Nav.Details -> openGame(game)
            Nav.First, Nav.Last -> { homeTarget = HomeTarget.Cover; select(if (nav == Nav.First) all.first() else all.last()) }
            else -> Unit
        }
    }

    private fun moveHome(target: HomeTarget) { homeTarget = target; sound(SoundEvent.Move, step++) }

    private fun libraryNav(nav: Nav) {
        val games = library
        val key = libraryKey ?: if (games.isEmpty()) emptyKey() else null
        if (key != null) return keyNav(nav, key)
        when (nav) {
            Nav.Up, Nav.Down, Nav.Left, Nav.Right -> {
                val dir = when (nav) { Nav.Up -> Dir.Up; Nav.Down -> Dir.Down; Nav.Left -> Dir.Left; else -> Dir.Right }
                if (nav == Nav.Up && libraryFocus < columns) { libraryKey = emptyKey(); sound(SoundEvent.Move, step++); return }
                val next = gridMove(libraryFocus, games.size, columns, dir)
                if (next == libraryFocus) sound(SoundEvent.Deny) else { libraryFocus = next; sound(SoundEvent.Move, step++) }
            }
            Nav.Confirm, Nav.Details -> games.getOrNull(libraryFocus)?.let { openGame(it) }
            Nav.Sort -> sort(!prefs.byName)
            Nav.First, Nav.Last -> { libraryFocus = if (nav == Nav.First) 0 else games.lastIndex; sound(SoundEvent.Move, step++) }
            else -> Unit
        }
    }

    /** The key the ring goes to when it leaves the covers: the tab in view. */
    private fun emptyKey() = if (onlyFavorites) LibraryKey.Favorites else LibraryKey.All

    private fun keyNav(nav: Nav, key: LibraryKey) {
        libraryKey = key
        when (nav) {
            Nav.Left, Nav.Right -> LibraryKey.entries.getOrNull(key.ordinal + if (nav == Nav.Right) 1 else -1)
                ?.let { libraryKey = it; sound(SoundEvent.Move, step++) } ?: sound(SoundEvent.Deny)
            Nav.Down -> if (library.isNotEmpty()) { libraryKey = null; sound(SoundEvent.Move, step++) } else sound(SoundEvent.Deny)
            Nav.Confirm -> when (key) {
                LibraryKey.All -> filter(false)
                LibraryKey.Favorites -> filter(true)
                LibraryKey.Search -> search()
                LibraryKey.Sort -> sort(!prefs.byName)
            }
            Nav.Sort -> sort(!prefs.byName)
            else -> sound(SoundEvent.Deny)
        }
    }

    fun sort(byName: Boolean) {
        val here = library.getOrNull(libraryFocus)
        prefs.saveByName(byName)
        here?.let { libraryFocus = library.indexOf(it).coerceAtLeast(0) }
        sound(SoundEvent.Select)
    }

    private fun textNav(nav: Nav) {
        if (nav == Nav.Down) textSteps++ else if (nav == Nav.Up) textSteps--
    }

    /** The line the controller is on, in the list on screen. The first one until it moves. */
    fun focusedRow(): String? {
        val ids = rowIds()
        return rowFocus[pageKey]?.takeIf { it in ids } ?: ids.firstOrNull()
    }

    private val pageKey: String get() = if (menuGame != null) MENU else route?.key ?: section.name
    private fun rowIds() = (if (menuGame == null && route is Route.GamePage) listOf(PLAY) else emptyList()) +
        sections().flatMap { it.rows }.filter { it.kind != Kind.Info }.map { it.id }

    private fun listNav(nav: Nav) {
        val ids = rowIds()
        val here = focusedRow() ?: return
        when (nav) {
            Nav.Up, Nav.Down -> {
                val next = ids.indexOf(here) + if (nav == Nav.Down) 1 else -1
                if (next in ids.indices) { rowFocus = rowFocus + (pageKey to ids[next]); sound(SoundEvent.Move, step++) } else sound(SoundEvent.Deny)
            }
            Nav.Left, Nav.Right -> {
                val kind = sections().flatMap { it.rows }.firstOrNull { it.id == here }?.kind
                if (kind is Kind.Toggle && kind.on != (nav == Nav.Right)) press(here) else sound(SoundEvent.Deny)
            }
            Nav.Confirm -> press(here)
            Nav.First, Nav.Last -> { rowFocus = rowFocus + (pageKey to if (nav == Nav.First) ids.first() else ids.last()); sound(SoundEvent.Move, step++) }
            else -> Unit
        }
    }

    /** A line pressed, by the finger or by the controller. */
    fun press(id: String) {
        val page = route
        if (id == PLAY && menuGame == null && page is Route.GamePage) { game(page.packageName)?.let { play(it) }; return }
        val row = sections().flatMap { it.rows }.firstOrNull { it.id == id } ?: return
        rowFocus = rowFocus + (pageKey to id)
        when (val kind = row.kind) {
            Kind.Info -> Unit
            is Kind.Open -> open(kind.route)
            is Kind.Press -> { sound(SoundEvent.Confirm); kind.run() }
            is Kind.Toggle -> { kind.set(!kind.on); sound(SoundEvent.Select) }
            is Kind.Pick -> { kind.run(); sound(SoundEvent.Select) }
        }
    }

    // ---- games --------------------------------------------------------------------------------------------

    fun play(game: Game) {
        if (demo) { message = context.getString(R.string.demo_game); sound(SoundEvent.Deny); return }
        if (GameLauncher.play(context, game)) {
            sound(SoundEvent.Play)
            selectedPackage = game.packageName
            prefs.saveStarted(game.packageName, System.currentTimeMillis())
        } else {
            fail(game)
        }
    }

    fun androidPage(game: Game) {
        sound(SoundEvent.Open)
        if (!GameLauncher.appInfo(screen, game)) fail(game)
    }

    private fun fail(game: Game) {
        message = context.getString(R.string.launch_failed, game.title)
        sound(SoundEvent.Deny)
        rescan()
    }

    fun lastStart(game: Game): Label = when (val last = LastStart.of(prefs.started[game.packageName], System.currentTimeMillis(), ZoneId.systemDefault())) {
        LastStart.Never -> Label.Res(R.string.started_never)
        LastStart.Today -> Label.Res(R.string.started_today)
        LastStart.Yesterday -> Label.Res(R.string.started_yesterday)
        is LastStart.Days -> Label.Res(R.string.started_days, last.count)
        is LastStart.OnDate -> Label.Res(R.string.started_on, DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(last.millis)))
    }

    // ---- the lists ----------------------------------------------------------------------------------------

    /** The lines the controller and the finger act on: the open menu's, else the page's. */
    fun sections(): List<RowSection> = menuGame?.let { menuSections(it) } ?: pageSections()

    fun pageSections(): List<RowSection> = when (val page = route) {
        is Route.GamePage -> game(page.packageName)?.let { gameSections(it) }.orEmpty()
        Route.Sounds -> soundSections()
        Route.Buttons -> listOf(RowSection(footer = Label.Res(R.string.controllers_layout), rows = listOf(swapRow())))
        Route.Cloud -> listOf(RowSection(rows = listOf(
            RowItem("calm", Label.Res(R.string.settings_calm), note = Label.Res(R.string.settings_calm_note), glyph = Glyph.Cloud,
                kind = Kind.Toggle(prefs.calm) { prefs.saveCalm(it) }),
        )))
        Route.Thanks -> thanksSections()
        Route.WhichGames, Route.PadTest, is Route.Licence -> emptyList()
        null -> when (section) {
            Section.Controllers -> padSections()
            Section.Settings -> settingsSections()
            else -> emptyList()
        }
    }

    /** The Mac's order (play, then the game, then what removes it); a line this system lacks is left out. */
    private fun menuSections(game: Game): List<RowSection> {
        fun row(id: String, title: Int, glyph: Glyph, note: Label? = null, danger: Boolean = false, run: () -> Unit) =
            RowItem(id, Label.Res(title), note = note, glyph = glyph, danger = danger, kind = Kind.Press { closeMenu(); run() })
        val page = route
        return listOf(RowSection(footer = Label.Res(R.string.detail_uninstall_warning), rows = listOfNotNull(
            row("menu-play", R.string.detail_play, Glyph.Play) { play(game) },
            if (page is Route.GamePage && page.packageName == game.packageName) null else row("menu-details", R.string.game_page, Glyph.Info) { openGame(game) },
            favorite(game).let { on -> row("menu-favorite", if (on) R.string.favorite_remove else R.string.favorite_add, Glyph.Heart) { toggleFavorite(game) } },
            row("menu-android", R.string.detail_info, Glyph.Device) { androidPage(game) },
            row("menu-uninstall", R.string.detail_uninstall, Glyph.Trash, Label.Res(R.string.detail_uninstall_note), danger = true) { androidPage(game) },
        )))
    }

    fun favorite(game: Game): Boolean = game.packageName in prefs.favorites

    private fun swapRow() = RowItem("swap", Label.Res(R.string.settings_swap), note = Label.Res(R.string.settings_swap_note), glyph = Glyph.Swap,
        kind = Kind.Toggle(prefs.swapAB) { prefs.saveSwapAB(it) })

    private fun gameSections(game: Game): List<RowSection> {
        val facts = listOfNotNull(
            RowItem("version", Label.Res(R.string.detail_version_label), value = Label.Raw(game.versionName.ifEmpty { "—" })),
            Nx2Android.titleId(game.packageName)?.let { RowItem("title", Label.Res(R.string.detail_title_id), note = Label.Raw(it)) },
            RowItem("package", Label.Res(R.string.detail_package), note = Label.Raw(game.packageName)),
        )
        return listOf(
            RowSection(rows = facts),
            RowSection(Label.Res(R.string.detail_in_game), rows = listOf(
                RowItem("pause", Label.Res(R.string.detail_pause_title), note = Label.Res(R.string.detail_pause_menu), glyph = Glyph.Sliders),
            )),
            RowSection(Label.Res(R.string.detail_on_device), footer = Label.Res(R.string.detail_uninstall_warning), rows = listOf(
                RowItem("favorite", Label.Res(R.string.favorite), glyph = Glyph.Heart, kind = Kind.Toggle(favorite(game)) { toggleFavorite(game, say = false) }),
                RowItem("android", Label.Res(R.string.detail_info), glyph = Glyph.Device, kind = Kind.Press { androidPage(game) }),
                RowItem("uninstall", Label.Res(R.string.detail_uninstall), note = Label.Res(R.string.detail_uninstall_note), glyph = Glyph.Trash, danger = true,
                    kind = Kind.Press { androidPage(game) }),
            )),
        )
    }

    private fun padSections(): List<RowSection> {
        val connected = pads.map {
            RowItem("pad${it.id}", Label.Raw(it.name), glyph = Glyph.Pad,
                note = Label.Res(R.string.controllers_ids, "%04x".format(it.vendor), "%04x".format(it.product)))
        }.ifEmpty { listOf(RowItem("none", Label.Res(R.string.controllers_none_title), note = Label.Res(R.string.controllers_none), glyph = Glyph.Pad)) }
        return listOf(
            RowSection(Label.Res(R.string.controllers_connected), rows = connected + RowItem("test", Label.Res(R.string.controllers_test), glyph = Glyph.Dots, kind = Kind.Open(Route.PadTest))),
            RowSection(Label.Res(R.string.controllers_buttons), footer = Label.Res(R.string.controllers_layout), rows = listOf(swapRow())),
        )
    }

    private fun settingsSections() = listOf(
        RowSection(Label.Res(R.string.settings_games), rows = listOf(
            RowItem("rescan", Label.Res(R.string.empty_rescan), glyph = Glyph.Refresh, kind = Kind.Press { rescan(say = true) }, value = Label.Res(R.string.library_count, count)),
            RowItem("which", Label.Res(R.string.settings_which), glyph = Glyph.Info, kind = Kind.Open(Route.WhichGames)),
        )),
        RowSection(Label.Res(R.string.settings_feel), rows = listOf(
            RowItem("sounds", Label.Res(R.string.settings_sound), glyph = Glyph.Sound, kind = Kind.Open(Route.Sounds),
                value = if (prefs.sound) Label.Raw(packName(prefs.pack)) else Label.Res(R.string.off)),
            RowItem("buttons", Label.Res(R.string.controllers_buttons), glyph = Glyph.Swap, kind = Kind.Open(Route.Buttons),
                value = Label.Res(R.string.settings_confirms, keyName(HintKey.Confirm))),
            RowItem("cloud", Label.Res(R.string.settings_cloud), glyph = Glyph.Cloud, kind = Kind.Open(Route.Cloud),
                value = Label.Res(if (prefs.calm) R.string.settings_cloud_still else R.string.settings_cloud_moving)),
        )),
        RowSection(Label.Res(R.string.settings_about), footer = Label.Res(R.string.settings_license), rows = listOf(
            RowItem("version", Label.Res(R.string.detail_version_label), value = Label.Raw(versionName), glyph = Glyph.Info),
            RowItem("thanks", Label.Res(R.string.settings_thanks), glyph = Glyph.Heart, kind = Kind.Open(Route.Thanks)),
        )),
    )

    private fun soundSections() = listOf(
        RowSection(footer = Label.Res(R.string.settings_sound_note), rows = listOf(
            RowItem("sound", Label.Res(R.string.settings_sound), glyph = Glyph.Sound, kind = Kind.Toggle(prefs.sound) { prefs.saveSound(it) }),
        )),
        RowSection(Label.Res(R.string.settings_pack), rows = OortSynth.packs.map { pack ->
            RowItem(pack, Label.Raw(packName(pack)), kind = Kind.Pick(prefs.pack == pack) { prefs.savePack(pack) })
        }),
    )

    private fun thanksSections(): List<RowSection> {
        fun text(text: LicenceText, title: Label = Label.Raw(text.title), note: Label? = null) =
            RowItem(text.name, title, note = note, glyph = Glyph.Text, kind = Kind.Open(Route.Licence(text)))
        return listOf(
            RowSection(rows = listOf(RowItem("oort", Label.Raw("Oort NX"), note = Label.Res(R.string.thanks_oort), glyph = Glyph.Heart))),
            RowSection(Label.Res(R.string.thanks_games), rows = listOf(
                RowItem("nx2android", Label.Raw("nx2android"), note = Label.Res(R.string.thanks_nx2android)),
                RowItem("nxnative", Label.Raw("nxnative"), note = Label.Res(R.string.thanks_nxnative)),
            )),
            RowSection(Label.Res(R.string.thanks_texts), rows = listOf(
                text(LicenceText.Oort, note = Label.Res(R.string.thanks_text_oort)),
                text(LicenceText.Notices, note = Label.Res(R.string.thanks_text_notices)),
                text(LicenceText.Apache, note = Label.Res(R.string.thanks_text_apache)),
            )),
        )
    }

    private fun packName(pack: String) = pack.replaceFirstChar { it.uppercase() }

    fun sound(event: SoundEvent, step: Int = 0) = soundPlayer.play(event, step)

    companion object {
        /** The play key of a game's page, which is not a line of its list. */
        const val PLAY = "play"
        private const val MENU = "menu"

        private val DEMO_GAMES = List(7) { i ->
            Game("org.nx2a.demo$i", "Demonstration ${i + 1}", "1.${i}.0", 65_537L + i, null)
        }
    }
}
