package io.github.sofianbll.oortnx.ui

import android.content.SharedPreferences
import io.github.sofianbll.oortnx.core.Game
import io.github.sofianbll.oortnx.core.Nav
import io.github.sofianbll.oortnx.core.Prefs
import java.lang.reflect.Proxy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class AppStateTest {
    private val games = listOf("Aube", "Brume", "Comète").mapIndexed { n, title ->
        Game("org.nx2a.test$n", title, "1.0", 1L, null)
    }
    private var installed = games
    private val launched = mutableListOf<Game>()
    private val prefs = inMemoryPrefs()

    private fun app() = AppState(prefs, demo = false, versionName = "test",
        text = { _, _ -> "" },
        scan = { take -> take(installed, emptyMap()) },
        launch = { launched.add(it) },
        appInfo = { true },
        playSound = { _, _ -> },
        openLink = { error("Unexpected credit link") },
        loadCredits = { error("Unexpected credits screen") },
    )

    @Test fun confirmationInAnEmptyLibraryScansAgain() {
        for (keyboard in listOf(false, true)) {
            installed = emptyList()
            val state = app()
            state.rescan()
            state.goTo(Section.Library)
            state.keyboard = keyboard
            installed = games
            state.onNav(Nav.Confirm)
            assertEquals(games, state.library)
        }
    }

    @Test fun searchShortcutDoesNotOpenAnInvisibleField() {
        installed = emptyList()
        val state = app()
        state.rescan()
        for (keyboard in listOf(false, true)) {
            state.keyboard = keyboard
            state.onNav(Nav.Search)
            assertEquals(Section.Home, state.section)
            assertFalse(state.searching)
        }
    }

    @Test fun aGameMovingToTheFrontIsStillTheTargetOfOptions() {
        val state = app()
        state.rescan()
        state.goTo(Section.Library)
        state.onNav(Nav.Right)
        state.onNav(Nav.Options)
        assertEquals(games[1], state.menuGame)
        state.onNav(Nav.Confirm)
        assertEquals(listOf(games[1]), launched)
        assertEquals(games[1], state.library.first())
        state.onNav(Nav.Options)
        assertEquals(games[1], state.menuGame)
    }

    @Test fun afterAProcessRestartAndRemovalFocusStaysOnTheSameGame() {
        val before = app()
        before.rescan()
        before.goTo(Section.Library)
        before.onNav(Nav.Right)
        installed = games.drop(1)
        val after = app()
        after.restore(before.snapshot())
        after.rescan()
        after.onNav(Nav.Details)
        assertEquals(Route.GamePage(games[1].packageName), after.route)
    }

    @Test fun theOldIndexIsOnlyAFallbackWhenTheFocusedGameIsGone() {
        val state = app()
        state.rescan()
        state.goTo(Section.Library)
        state.onNav(Nav.Right)
        installed = listOf(games[0], games[2])
        state.rescan()
        state.onNav(Nav.Details)
        assertEquals(Route.GamePage(games[2].packageName), state.route)
    }

    @Test fun goingBackToSoundsConfirmsTheRestoredPackNotTheSwitch() {
        val before = app()
        before.goTo(Section.Settings)
        before.open(Route.Sounds)
        before.keyboard = true
        before.onNav(Nav.Down)
        before.onNav(Nav.Down)
        assertEquals("pollen", before.focusedRow())
        val after = app()
        after.restore(before.snapshot())
        assertEquals(Route.Sounds, after.route)
        after.onNav(Nav.Confirm)
        assertTrue(prefs.sound)
        assertEquals("pollen", prefs.pack)
    }

    @Test fun restoredRowShowsTheSameInputModeBeforeAnyButton() {
        val before = app()
        before.goTo(Section.Settings)
        before.open(Route.Sounds)
        before.keyboard = true
        before.onNav(Nav.Down)
        val after = app()
        after.restore(before.snapshot())
        assertTrue(after.padMode)
        assertTrue(after.keyboard)
    }

    @Test fun ctrlFRequestsFocusOnceEvenWhenThereIsAlreadyAQuery() {
        val state = app()
        state.rescan()
        state.keyboard = true
        state.onNav(Nav.Search)
        assertTrue(state.takeFieldRequest())
        state.type("brume")
        state.leaveField()
        state.onNav(Nav.Search)
        assertTrue(state.takeFieldRequest())
        assertFalse(state.takeFieldRequest())
        assertEquals("brume", state.query)
    }

    @Test fun largePastesCannotGrowTheQuerySavedToAndroid() {
        val state = app()
        val paste = "a".repeat(180_000)
        repeat(4) { state.type(state.query + paste) }
        assertEquals(256, state.snapshot().query.length)
    }

    @Test fun restoringAnOversizedQueryDoesNotKeepHalfOfAnEmoji() {
        val state = app()
        val prefix = "é".repeat(255)
        state.restore(state.snapshot().copy(query = "$prefix🙂z"))
        assertEquals(prefix, state.query)
    }

    private fun inMemoryPrefs(): Prefs {
        val values = mutableMapOf<String, Any?>()
        val store = Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences::class.java)) { _, method, args ->
            when (method.name) {
                "contains" -> values.containsKey(args[0])
                "getBoolean", "getString", "getStringSet" -> values.getOrDefault(args[0] as String, args[1])
                "getAll" -> values
                "edit" -> Proxy.newProxyInstance(javaClass.classLoader, arrayOf(SharedPreferences.Editor::class.java)) { editor, edit, params ->
                    when (edit.name) {
                        "putBoolean", "putString", "putStringSet", "putLong" -> editor.also { values[params[0] as String] = params[1] }
                        "apply" -> null
                        else -> error(edit.name)
                    }
                }
                else -> error(method.name)
            }
        } as SharedPreferences
        return Prefs(store) { false to false }
    }
}
