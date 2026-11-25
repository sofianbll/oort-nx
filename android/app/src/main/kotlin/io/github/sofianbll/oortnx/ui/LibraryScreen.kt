package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game

@Composable
fun LibraryScreen(state: AppState, modifier: Modifier = Modifier) {
    val calm = state.prefs.calm
    BoxWithConstraints(modifier.fillMaxSize()) {
        val tall = maxHeight > maxWidth
        val gap = 12.dp
        val margin = 20.dp
        val topGap = if (tall) maxHeight * 0.24f else 24.dp
        val columns = ((maxWidth - margin * 2 + gap) / (CELL + gap)).toInt().coerceAtLeast(1)
        SideEffect { state.columns = columns }
        val grid = rememberLazyGridState()
        LaunchedEffect(state.libraryFocus, state.padMode) {
            if (state.padMode && state.games.isNotEmpty()) grid.animateScrollToItem(state.libraryFocus)
        }
        Column(Modifier.fillMaxSize().padding(horizontal = margin)) {
            // Upright, the cloud has the top of the window: the title sits at its left and the games start lower.
            Spacer(Modifier.height(topGap))
            Text(stringResource(R.string.library_title), style = MaterialTheme.typography.headlineMedium)
            Text(
                when {
                    !state.scanned -> stringResource(R.string.library_scanning)
                    state.games.isEmpty() -> ""
                    state.padMode -> stringResource(R.string.library_hint)
                    else -> stringResource(R.string.library_count, state.games.size)
                },
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(16.dp))
            if (state.scanned && state.games.isEmpty()) {
                EmptyLibrary(state)
            } else {
                LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    state = grid,
                    horizontalArrangement = Arrangement.spacedBy(gap),
                    verticalArrangement = Arrangement.spacedBy(gap),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(state.games, key = { _, g -> g.packageName }) { index, game ->
                        GameTile(
                            game = game,
                            icon = state.icons[game.packageName],
                            focused = state.padMode && index == state.libraryFocus,
                            calm = calm,
                            onClick = { state.padMode = false; state.open(game) },
                        )
                    }
                }
            }
        }
    }
}

private val CELL = 150.dp

@Composable
private fun GameTile(game: Game, icon: ImageBitmap?, focused: Boolean, calm: Boolean, onClick: () -> Unit) {
    val shape = RoundedCornerShape(canvas(OortTokens.Radius.Card))
    FocusRing(focused, calm, shape) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(OortTokens.Palette.Glass.copy(alpha = 0.82f))
                .clickable(onClick = onClick)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            val art = Modifier.size(72.dp).clip(RoundedCornerShape(canvas(OortTokens.Radius.Content)))
            if (icon != null) {
                Image(icon, contentDescription = null, modifier = art, contentScale = ContentScale.Crop)
            } else {
                Spacer(art.background(OortTokens.Primitive.OrbitHigh))
            }
            Text(game.title, style = MaterialTheme.typography.titleSmall, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                game.versionName,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun EmptyLibrary(state: AppState) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp), horizontalAlignment = Alignment.Start) {
        Text(stringResource(R.string.empty_title), style = MaterialTheme.typography.titleLarge)
        Text(
            stringResource(R.string.empty_body),
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth(0.9f),
        )
        OutlinedButton(onClick = { state.rescan() }) { Text(stringResource(R.string.empty_rescan)) }
    }
}
