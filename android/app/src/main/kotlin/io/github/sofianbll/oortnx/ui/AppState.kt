package io.github.sofianbll.oortnx.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Dir
import io.github.sofianbll.oortnx.core.Game
import io.github.sofianbll.oortnx.core.GameLauncher
import io.github.sofianbll.oortnx.core.GameScanner
import io.github.sofianbll.oortnx.core.Nav
import io.github.sofianbll.oortnx.core.OortSynth
import io.github.sofianbll.oortnx.core.Prefs
import io.github.sofianbll.oortnx.core.SoundEvent
import io.github.sofianbll.oortnx.core.SoundPlayer
import io.github.sofianbll.oortnx.core.gridMove
import kotlin.concurrent.thread

enum class Section { Library, Controllers, Settings }

/** What is on screen and where the focus is. Kept by hand, with no framework: it is small, and the activity is never recreated. */
class AppState(
    private val context: Context,
    val prefs: Prefs,
    private val soundPlayer: SoundPlayer,
    /** A debuggable build started with `--ez demo true` shows made-up entries, to look at the screens without a game. */
    private val demo: Boolean,
) {
    var section by mutableStateOf(Section.Library)
    var detail by mutableStateOf<Game?>(null)
    var games by mutableStateOf<List<Game>>(emptyList())
    var icons by mutableStateOf<Map<String, ImageBitmap>>(emptyMap())
    var scanned by mutableStateOf(false)
    /** True once a pad or a keyboard moved the focus; a touch puts it back to false. */
    var padMode by mutableStateOf(false)
    var libraryFocus by mutableIntStateOf(0)
    var detailFocus by mutableIntStateOf(0)
    var settingsFocus by mutableIntStateOf(0)
    var columns by mutableIntStateOf(2)
    var lastKey by mutableStateOf<String?>(null)
    var message by mutableStateOf<String?>(null)
    private var step = 0

    fun rescan() {
        thread(name = "oort-scan", isDaemon = true) {
            val found = if (demo) DEMO_GAMES else GameScanner.scan(context)
            val pictures = found.mapNotNull { game -> icon(game)?.let { game.packageName to it } }.toMap()
            games = found
            icons = pictures
            libraryFocus = libraryFocus.coerceIn(0, (found.size - 1).coerceAtLeast(0))
            scanned = true
        }
    }

    private fun icon(game: Game): ImageBitmap? = try {
        val drawable = context.packageManager.getApplicationIcon(game.packageName)
        val bitmap = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, 192, 192)
        drawable.draw(Canvas(bitmap))
        bitmap.asImageBitmap()
    } catch (_: Exception) {
        null // a demo entry, or a package that went away
    }

    // ---- what a button does -------------------------------------------------------------------------------

    fun onNav(nav: Nav) {
        padMode = true
        when (nav) {
            Nav.Next -> return cycle(1)
            Nav.Previous -> return cycle(-1)
            else -> Unit
        }
        val game = detail
        when {
            game != null -> detailNav(nav, game)
            section == Section.Library -> libraryNav(nav)
            section == Section.Settings -> settingsNav(nav)
            else -> if (nav == Nav.Back) goTo(Section.Library)
        }
    }

    /** The system's Back (gesture or key). False when there is nothing left to go back to: Android then leaves the app. */
    fun onBack(): Boolean = when {
        detail != null -> { closeDetail(); true }
        section != Section.Library -> { goTo(Section.Library); true }
        else -> false
    }

    fun goTo(next: Section) {
        if (next == section && detail == null) return
        section = next
        detail = null
        sound(SoundEvent.Move)
    }

    private fun cycle(by: Int) {
        val all = Section.entries
        goTo(all[(section.ordinal + by + all.size) % all.size])
    }

    fun open(game: Game) {
        libraryFocus = games.indexOf(game).coerceAtLeast(0)
        detailFocus = 0
        detail = game
        sound(SoundEvent.Open)
    }

    fun closeDetail() {
        detail = null
        sound(SoundEvent.Back)
    }

    private fun libraryNav(nav: Nav) {
        when (nav) {
            Nav.Up, Nav.Down, Nav.Left, Nav.Right -> {
                val dir = when (nav) { Nav.Up -> Dir.Up; Nav.Down -> Dir.Down; Nav.Left -> Dir.Left; else -> Dir.Right }
                val next = gridMove(libraryFocus, games.size, columns, dir)
                if (next != libraryFocus) { libraryFocus = next; sound(SoundEvent.Move, step++) }
            }
            Nav.Confirm -> games.getOrNull(libraryFocus)?.let { open(it) }
            Nav.Options -> rescan()
            else -> Unit
        }
    }

    private fun detailNav(nav: Nav, game: Game) {
        when (nav) {
            Nav.Up -> if (detailFocus > 0) { detailFocus--; sound(SoundEvent.Move, step++) }
            Nav.Down -> if (detailFocus < DETAIL_ACTIONS - 1) { detailFocus++; sound(SoundEvent.Move, step++) }
            Nav.Confirm -> activate(game, detailFocus)
            Nav.Back -> closeDetail()
            else -> Unit
        }
    }

    fun activate(game: Game, action: Int) {
        when (action) {
            0 -> play(game)
            1 -> { sound(SoundEvent.Confirm); if (!GameLauncher.appInfo(context, game)) fail(game) }
            else -> { sound(SoundEvent.Select); if (!GameLauncher.uninstall(context, game)) fail(game) }
        }
    }

    private fun play(game: Game) {
        if (demo) { message = context.getString(R.string.demo_game); sound(SoundEvent.Deny); return }
        if (GameLauncher.play(context, game)) sound(SoundEvent.Play) else fail(game)
    }

    private fun fail(game: Game) {
        message = context.getString(R.string.launch_failed, game.title)
        sound(SoundEvent.Deny)
    }

    private fun settingsNav(nav: Nav) {
        when (nav) {
            Nav.Up -> if (settingsFocus > 0) { settingsFocus--; sound(SoundEvent.Move, step++) }
            Nav.Down -> if (settingsFocus < SETTINGS_ROWS - 1) { settingsFocus++; sound(SoundEvent.Move, step++) }
            Nav.Confirm -> changeSetting(settingsFocus)
            Nav.Back -> goTo(Section.Library)
            else -> Unit
        }
    }

    fun changeSetting(row: Int) {
        when (row) {
            0 -> { prefs.saveSound(!prefs.sound); if (prefs.sound) sound(SoundEvent.Confirm) }
            1 -> {
                val packs = OortSynth.packs
                prefs.savePack(packs[(packs.indexOf(prefs.pack) + 1) % packs.size])
                sound(SoundEvent.Confirm)
            }
            2 -> { prefs.saveSwapAB(!prefs.swapAB); sound(SoundEvent.Confirm) }
            else -> { prefs.saveCalm(!prefs.calm); sound(SoundEvent.Confirm) }
        }
    }

    fun sound(event: SoundEvent, step: Int = 0) = soundPlayer.play(event, step)

    companion object {
        const val DETAIL_ACTIONS = 3
        const val SETTINGS_ROWS = 4

        private val DEMO_GAMES = List(7) { i ->
            Game("org.nx2a.demo$i", "Demonstration ${i + 1}", "1.${i}.0", 65_537L + i, null)
        }
    }
}
