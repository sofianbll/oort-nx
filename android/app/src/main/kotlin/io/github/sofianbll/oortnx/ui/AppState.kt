package io.github.sofianbll.oortnx.ui

import android.content.Context
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
import io.github.sofianbll.oortnx.core.PadMonitor
import io.github.sofianbll.oortnx.core.Prefs
import io.github.sofianbll.oortnx.core.SoundEvent
import io.github.sofianbll.oortnx.core.SoundPlayer
import io.github.sofianbll.oortnx.core.gridMove
import io.github.sofianbll.oortnx.core.lastStartedFirst
import java.text.DateFormat
import java.time.ZoneId
import java.util.Date
import kotlin.concurrent.thread

/** What the controller is on, in À la une. */
enum class HomeTarget { Cover, Play, Page, Android }

/** What is on screen and where the focus is. Kept by hand, with no framework: it is small, and the activity is never recreated. */
class AppState(
    private val context: Context,
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
    val library: List<Game> get() = if (prefs.byName) found else recent
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

    /** Up and down on a page of text, for the page to follow. */
    var textSteps by mutableIntStateOf(0)
        private set
    var pads by mutableStateOf<List<ConnectedPad>>(emptyList())
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
        libraryFocus = libraryFocus.coerceIn(0, (games.size - 1).coerceAtLeast(0))
        // The page of a game that went away closes by itself.
        val gone = { r: Route -> r is Route.GamePage && games.none { it.packageName == r.packageName } }
        if (stacks.values.any { it.any(gone) }) stacks = stacks.mapValues { (_, pages) -> pages.takeWhile { !gone(it) } }
        scanned = true
    }

    // ---- moving about -------------------------------------------------------------------------------------

    /** The bar and the rail. The section already open goes back to its first page. */
    fun goTo(next: Section) {
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
        if (route != null) stacks = stacks + (section to stacks[section].orEmpty().dropLast(1))
        else section = Section.Home
        sound(SoundEvent.Back)
        return true
    }

    val canGoBack: Boolean get() = route != null || section != Section.Home

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

    // ---- what a button does -------------------------------------------------------------------------------

    fun onNav(nav: Nav) {
        padMode = true
        when (nav) {
            Nav.Next -> return cycle(1)
            Nav.Previous -> return cycle(-1)
            Nav.Controllers -> return goTo(Section.Controllers)
            Nav.Settings -> return goTo(Section.Settings)
            Nav.Back -> { if (!onBack()) sound(SoundEvent.Deny); return }
            else -> Unit
        }
        val page = route
        when {
            page is Route.Licence -> textNav(nav)
            page != null -> listNav(nav)
            section == Section.Home -> homeNav(nav)
            section == Section.Library -> libraryNav(nav)
            else -> listNav(nav)
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
            Nav.Options -> openGame(game)
            else -> Unit
        }
    }

    private fun moveHome(target: HomeTarget) { homeTarget = target; sound(SoundEvent.Move, step++) }

    private fun libraryNav(nav: Nav) {
        val games = library
        if (games.isEmpty()) { if (nav == Nav.Confirm) rescan(); return }
        when (nav) {
            Nav.Up, Nav.Down, Nav.Left, Nav.Right -> {
                val dir = when (nav) { Nav.Up -> Dir.Up; Nav.Down -> Dir.Down; Nav.Left -> Dir.Left; else -> Dir.Right }
                val next = gridMove(libraryFocus, games.size, columns, dir)
                if (next == libraryFocus) sound(SoundEvent.Deny) else { libraryFocus = next; sound(SoundEvent.Move, step++) }
            }
            Nav.Confirm -> games.getOrNull(libraryFocus)?.let { openGame(it) }
            Nav.Options -> sort(!prefs.byName)
            else -> Unit
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

    private val pageKey: String get() = route?.key ?: section.name
    private fun rowIds() = (if (route is Route.GamePage) listOf(PLAY) else emptyList()) +
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
            else -> Unit
        }
    }

    /** A line pressed, by the finger or by the controller. */
    fun press(id: String) {
        val page = route
        if (id == PLAY && page is Route.GamePage) { game(page.packageName)?.let { play(it) }; return }
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
        if (!GameLauncher.appInfo(context, game)) fail(game)
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

    fun sections(): List<RowSection> = when (val page = route) {
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
                value = Label.Res(if (prefs.swapAB) R.string.settings_confirm_b else R.string.settings_confirm_a)),
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

        private val DEMO_GAMES = List(7) { i ->
            Game("org.nx2a.demo$i", "Demonstration ${i + 1}", "1.${i}.0", 65_537L + i, null)
        }
    }
}
