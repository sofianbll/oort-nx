package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game

/** The game's page: what it is, Play, and the honest limits of a launcher that is not the game. */
@Composable
fun GameScreen(state: AppState, game: Game) {
    val sections = state.sections()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // Room for the cover beside the list: a tablet, or a phone on its side.
        if (maxWidth > maxHeight && maxWidth >= 600.dp) {
            val side = minOf(maxHeight * 0.45f, 340.dp, maxWidth * 0.36f)
            Row(Modifier.fillMaxSize().padding(horizontal = 24.dp), horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                Column(Modifier.weight(0.42f).widthIn(max = 520.dp).fillMaxHeight()) {
                    PageTitle(stringResource(R.string.game_page), { state.onBack() })
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) { Header(state, game, side) }
                    PlayKey(state, game, Modifier.padding(vertical = 8.dp))
                }
                Column(Modifier.weight(0.58f).fillMaxHeight()) {
                    val scroll = rememberScrollState()
                    Column(Modifier.weight(1f).verticalScroll(scroll).widthIn(max = 780.dp).padding(top = 24.dp, bottom = 24.dp)) { OortList(state, sections) }
                    PageHints(state)
                }
            }
        } else {
            val side = minOf(maxWidth - 40.dp, maxHeight * 0.34f)
            Column(Modifier.fillMaxSize()) {
                PageTitle(stringResource(R.string.game_page), { state.onBack() }, Modifier.padding(horizontal = 20.dp))
                val scroll = rememberScrollState()
                val first = state.padMode && state.focusedRow() == AppState.PLAY
                LaunchedEffect(first) { if (first) scroll.animateScrollTo(0) }
                Box(Modifier.weight(1f)) {
                    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(start = 20.dp, end = 20.dp, bottom = 40.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
                        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) { Header(state, game, side) }
                        OortList(state, sections, Modifier.widthIn(max = 780.dp))
                    }
                    Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(40.dp).background(Brush.verticalGradient(listOf(Color.Transparent, OortTokens.Palette.Scrim.copy(alpha = 0.9f)))))
                }
                // The one action stays under the thumb however far the list goes.
                Column(Modifier.fillMaxWidth().background(OortTokens.Palette.Scrim.copy(alpha = 0.9f)).padding(horizontal = 15.dp).padding(bottom = 8.dp)) {
                    PlayKey(state, game, max = 790.dp)
                    PageHints(state)
                }
            }
        }
    }
}

@Composable
private fun Header(state: AppState, game: Game, side: Dp) {
    GameCover(game, state.icons[game.packageName], focused = false, calm = state.prefs.calm, modifier = Modifier.size(side))
    Text(game.title, Modifier.heading(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
    StateLine(state.lastStart(game).text())
}

@Composable
private fun PlayKey(state: AppState, game: Game, modifier: Modifier = Modifier, max: Dp = 560.dp) {
    OortKey(
        { state.play(game) }, state.prefs.calm, modifier.widthIn(max = max).fillMaxWidth(), solid = true,
        focused = state.padMode && state.focusedRow() == AppState.PLAY, glyph = Glyph.Play, label = stringResource(R.string.detail_play),
    )
}

@Composable
fun PageHints(state: AppState) = Hints(state, listOf(state.confirmKey to stringResource(R.string.select), state.backKey to stringResource(R.string.back)))
