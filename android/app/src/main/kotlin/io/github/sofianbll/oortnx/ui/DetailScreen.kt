package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game

/** The game's page: what it is, Play, and the honest limits of a launcher that is not the game. */
@Composable
fun DetailScreen(state: AppState, game: Game, modifier: Modifier = Modifier) {
    val calm = state.prefs.calm
    val shape = RoundedCornerShape(canvas(OortTokens.Radius.Card))
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalAlignment = Alignment.CenterVertically) {
            val icon = state.icons[game.packageName]
            val art = Modifier.size(96.dp).clip(RoundedCornerShape(canvas(OortTokens.Radius.Card)))
            if (icon != null) Image(icon, null, art, contentScale = ContentScale.Crop)
            else Spacer(art.background(OortTokens.Primitive.OrbitHigh))
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(game.title, style = MaterialTheme.typography.headlineMedium)
                Text(
                    stringResource(R.string.detail_version, game.versionName),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(game.packageName, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        val actions = Modifier.widthIn(max = 420.dp).fillMaxWidth()
        FocusRing(state.padMode && state.detailFocus == 0, calm, ButtonDefaults.shape, actions) {
            Button({ state.activate(game, 0) }, Modifier.fillMaxWidth().heightIn(min = 56.dp)) {
                OortGlyph(Glyph.Play, tint = OortTokens.Palette.OnFocus)
                Text(stringResource(R.string.detail_play), Modifier.padding(start = 8.dp), style = MaterialTheme.typography.titleMedium)
            }
        }
        FocusRing(state.padMode && state.detailFocus == 1, calm, ButtonDefaults.outlinedShape, actions) {
            OutlinedButton({ state.activate(game, 1) }, Modifier.fillMaxWidth().heightIn(min = 52.dp)) {
                Text(stringResource(R.string.detail_info))
            }
        }
        FocusRing(state.padMode && state.detailFocus == 2, calm, ButtonDefaults.textShape, actions) {
            TextButton(
                { state.activate(game, 2) },
                Modifier.fillMaxWidth().heightIn(min = 52.dp),
                colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.error),
            ) { Text(stringResource(R.string.detail_uninstall)) }
        }

        Text(
            stringResource(R.string.detail_pause_menu),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.widthIn(max = 520.dp),
        )
        Text(
            stringResource(R.string.detail_uninstall_warning),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.widthIn(max = 520.dp),
        )
    }
}
