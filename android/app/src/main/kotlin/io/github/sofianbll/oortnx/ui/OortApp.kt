package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
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
    BoxWithConstraints(Modifier.fillMaxSize().background(Scrim)) {
        val compact = maxWidth < 600.dp
        CloudBackdrop(calm = state.prefs.calm)
        Scaffold(
            containerColor = Color.Transparent,
            snackbarHost = { SnackbarHost(snackbar) },
            bottomBar = { if (compact) SectionBar(state) },
        ) { padding ->
            Row(Modifier.padding(padding).fillMaxSize()) {
                if (!compact) SectionRail(state)
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    val game = state.detail
                    when {
                        game != null -> DetailScreen(state, game)
                        state.section == Section.Library -> LibraryScreen(state)
                        state.section == Section.Controllers -> ControllersScreen(state)
                        else -> SettingsScreen(state)
                    }
                }
            }
        }
    }
}

private class Destination(val section: Section, val glyph: Glyph, val label: Int)

private val DESTINATIONS = listOf(
    Destination(Section.Library, Glyph.Library, R.string.nav_library),
    Destination(Section.Controllers, Glyph.Controllers, R.string.nav_controllers),
    Destination(Section.Settings, Glyph.Settings, R.string.nav_settings),
)

@Composable
private fun SectionBar(state: AppState) {
    NavigationBar(containerColor = OortTokens.Palette.Glass.copy(alpha = 0.92f)) {
        for (d in DESTINATIONS) {
            NavigationBarItem(
                selected = state.section == d.section,
                onClick = { state.padMode = false; state.goTo(d.section) },
                icon = { OortGlyph(d.glyph) },
                label = { Text(stringResource(d.label)) },
            )
        }
    }
}

@Composable
private fun SectionRail(state: AppState) {
    NavigationRail(containerColor = OortTokens.Palette.Glass.copy(alpha = 0.6f), windowInsets = WindowInsets(0)) {
        for (d in DESTINATIONS) {
            NavigationRailItem(
                selected = state.section == d.section,
                onClick = { state.padMode = false; state.goTo(d.section) },
                icon = { OortGlyph(d.glyph) },
                label = { Text(stringResource(d.label)) },
            )
        }
    }
}
