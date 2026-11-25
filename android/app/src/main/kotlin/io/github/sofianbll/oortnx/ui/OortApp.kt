package io.github.sofianbll.oortnx.ui

import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.github.sofianbll.oortnx.R

/**
 * Material's navigation, sized to the window: a bar under a phone held upright, a rail beside a wide window.
 * The cloud sits behind everything; the screens are transparent over it.
 */
@Composable
fun OortApp(state: AppState) {
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(state.message) {
        state.message?.let { snackbar.showSnackbar(it); state.message = null }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(OortTokens.Palette.Scrim)) {
        val compact = maxWidth < 600.dp
        // A phone on its side with a controller is a console: no system bar, and À la une takes the rail's place too.
        val console = state.padMode && maxWidth > maxHeight && maxHeight < 500.dp
        FullScreen(console)
        val route = state.route
        val home = route == null && state.section == Section.Home
        CloudBackdrop(still = state.prefs.stillCloud, strength = if (home) 1f else 0.5f)
        Scaffold(
            containerColor = Color.Transparent,
            contentColor = OortTokens.Palette.Ink,
            contentWindowInsets = WindowInsets.safeDrawing,
            snackbarHost = { SnackbarHost(snackbar) },
            bottomBar = { if (compact && route == null) SectionBar(state) },
        ) { padding ->
            Row(Modifier.padding(padding).consumeWindowInsets(padding).fillMaxSize()) {
                if (!compact && !(console && home)) SectionRail(state)
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    AnimatedContent(
                        targetState = state.section to route,
                        transitionSpec = {
                            if (state.prefs.calm) EnterTransition.None togetherWith ExitTransition.None
                            else fadeIn(tween(OortTokens.Motion.FocusInMs)) togetherWith fadeOut(tween(OortTokens.Motion.QuickMs))
                        },
                        label = "page",
                    ) { (section, page) ->
                        // What leaves the screen fades out as it was: only the page on top is drawn from the state.
                        if (section == state.section && page == state.route) Page(state, section, page)
                    }
                }
            }
        }
    }
}

@Composable
private fun Page(state: AppState, section: Section, page: Route?) {
    val back = { state.onBack(); Unit }
    when (page) {
        is Route.GamePage -> state.game(page.packageName)?.let { GameScreen(state, it) }
        Route.PadTest -> PadTestScreen(state)
        Route.Sounds -> ListScreen(state, stringResource(R.string.settings_sound), back)
        Route.Buttons -> ListScreen(state, stringResource(R.string.controllers_buttons), back)
        Route.Cloud -> ListScreen(state, stringResource(R.string.settings_cloud), back)
        Route.Integrations -> ListScreen(state, stringResource(R.string.integrations), back)
        Route.CloudLibrary -> { ListScreen(state, stringResource(R.string.cloud_library), back); CodeDialog(state) }
        Route.CloudOff -> ListScreen(state, stringResource(R.string.cloud_turn_off), back)
        is Route.CloudPage -> state.cloud?.let { cloud -> cloud.games.firstOrNull { it.title == page.title }?.let { CloudGameScreen(state, cloud, it) } }
        Route.WhichGames -> WhichGamesScreen(state)
        Route.Thanks -> ListScreen(state, stringResource(R.string.settings_thanks), back)
        is Route.Licence -> LicenceScreen(state, page.text)
        null -> when (section) {
            Section.Home -> HomeScreen(state)
            Section.Library -> LibraryScreen(state)
            Section.Controllers -> ListScreen(state, stringResource(R.string.nav_controllers), null)
            Section.Settings -> ListScreen(state, stringResource(R.string.nav_settings), null)
        }
    }
}

@Composable
private fun FullScreen(on: Boolean) {
    val window = LocalActivity.current?.window ?: return
    val view = LocalView.current
    DisposableEffect(on) {
        val bars = WindowCompat.getInsetsController(window, view)
        bars.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (on) bars.hide(WindowInsetsCompat.Type.systemBars()) else bars.show(WindowInsetsCompat.Type.systemBars())
        onDispose { }
    }
}

private class Destination(val section: Section, val glyph: Glyph, val label: Int)

private val DESTINATIONS = listOf(
    Destination(Section.Home, Glyph.Home, R.string.nav_home),
    Destination(Section.Library, Glyph.Library, R.string.nav_library),
    Destination(Section.Controllers, Glyph.Controllers, R.string.nav_controllers),
    Destination(Section.Settings, Glyph.Settings, R.string.nav_settings),
)

/** The places keep their whole names: past this size the text of the bar stops growing, as Android's own bars do. */
@Composable
private fun SteadyText(content: @Composable () -> Unit) {
    val now = LocalDensity.current
    CompositionLocalProvider(LocalDensity provides Density(now.density, now.fontScale.coerceAtMost(1.15f)), content = content)
}

@Composable
private fun SectionBar(state: AppState) = SteadyText {
    NavigationBar(containerColor = OortTokens.Palette.Glass.copy(alpha = 0.92f)) {
        for (d in DESTINATIONS) {
            NavigationBarItem(
                selected = state.section == d.section,
                onClick = { state.goTo(d.section) },
                icon = { OortGlyph(d.glyph) },
                label = { Text(stringResource(d.label), maxLines = 1, overflow = TextOverflow.Ellipsis) },
            )
        }
    }
}

@Composable
private fun SectionRail(state: AppState) = SteadyText {
    NavigationRail(containerColor = OortTokens.Palette.Glass.copy(alpha = 0.6f), windowInsets = WindowInsets(0)) {
        androidx.compose.foundation.layout.Column(
            Modifier.fillMaxHeight().verticalScroll(rememberScrollState()).padding(top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            for (d in DESTINATIONS) {
                NavigationRailItem(
                    selected = state.section == d.section,
                    onClick = { state.goTo(d.section) },
                    icon = { OortGlyph(d.glyph) },
                    label = { Text(stringResource(d.label), maxLines = 1, overflow = TextOverflow.Ellipsis) },
                )
            }
        }
    }
}
