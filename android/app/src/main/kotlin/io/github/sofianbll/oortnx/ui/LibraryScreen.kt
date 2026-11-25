package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game

/** Every game, the last started first or by name. The covers are as wide as the window allows, never smaller than a thumb. */
@Composable
fun LibraryScreen(state: AppState) {
    val games = state.library
    BoxWithConstraints(Modifier.fillMaxSize()) {
        if (state.count == 0) {
            if (state.scanned) EmptyLibrary(state, Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(28.dp))
            else Text(stringResource(R.string.library_scanning), Modifier.padding(28.dp), style = MaterialTheme.typography.bodyLarge, color = Ink2)
            return@BoxWithConstraints
        }
        val columns = (maxWidth / 172.dp).toInt().coerceAtLeast(2)
        SideEffect { state.columns = columns }
        val grid = rememberLazyGridState()
        LaunchedEffect(state.libraryFocus, state.padMode) {
            if (!state.padMode || games.isEmpty()) return@LaunchedEffect
            val info = grid.layoutInfo
            val seen = info.visibleItemsInfo.firstOrNull { it.index == state.libraryFocus }
            if (seen == null || seen.offset.y < 0 || seen.offset.y + seen.size.height > info.viewportEndOffset) grid.animateScrollToItem(state.libraryFocus)
        }
        LaunchedEffect(state.prefs.byName, state.onlyFavorites, state.query) { if (state.padMode) grid.animateScrollToItem(state.libraryFocus) else grid.scrollToItem(0) }
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
            LibraryHeader(state)
            // The field and the hints keep their room; in a low window only the keys need to scroll.
            Column(Modifier.weight(1f)) {
                if (state.padKeyboard) PadKeyboard(state)
                if (games.isEmpty()) NothingHere(state, Modifier.weight(1f))
                else LazyVerticalGrid(
                    columns = GridCells.Fixed(columns),
                    state = grid,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                    contentPadding = PaddingValues(bottom = 24.dp),
                    modifier = Modifier.weight(1f),
                ) {
                    itemsIndexed(games, key = { _, g -> g.packageName }) { index, game ->
                        GameTile(state, game, state.icons[game.packageName], focused = state.padMode && !state.typing && !state.padKeyboard && state.libraryKey == null && index == state.libraryFocus)
                    }
                }
            }
            val onCover = state.libraryKey == null && games.isNotEmpty()
            // In the field the keys type: only the way out is left to say.
            if (state.typing) Hints(state, listOf(HintKey.Back to R.string.close))
            else if (state.padKeyboard) Hints(state, listOf(
                HintKey.Confirm to R.string.select, HintKey.Details to R.string.key_erase, HintKey.Search to R.string.key_space,
                HintKey.Options to R.string.key_done, HintKey.Back to R.string.close,
            ))
            else Hints(state, listOfNotNull(
                HintKey.Confirm to if (onCover) R.string.game_page else R.string.select,
                if (onCover) HintKey.Options to R.string.options else null, HintKey.Search to R.string.search,
                if (onCover) HintKey.Sort to R.string.sort else null, HintKey.Tabs to R.string.hint_tabs, HintKey.Back to R.string.back,
            ))
        }
    }
}

/** No cover to show: the search found nothing, or there is no favourite yet. */
@Composable
private fun NothingHere(state: AppState, modifier: Modifier = Modifier) {
    val searched = state.query.isNotBlank()
    Column(modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = canvas(OortTokens.Space.FieldInset), vertical = canvas(OortTokens.Space.TitleGap)), verticalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.Line))) {
        Text(stringResource(if (searched) R.string.search_none else R.string.favorites_empty), Modifier.heading(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        if (!searched) Text(stringResource(R.string.favorites_how), Modifier.widthIn(max = canvas(OortTokens.Space.TransferMeasure)), style = MaterialTheme.typography.bodyLarge, color = Ink2)
    }
}

@Composable
private fun GameTile(state: AppState, game: Game, icon: ImageBitmap?, focused: Boolean) {
    val source = remember { MutableInteractionSource() }
    val hovered by source.collectIsHoveredAsState()
    Column(
        Modifier
            .fillMaxWidth()
            .onRightClick { state.openMenu(game) }
            .combinedClickable(source, indication = null, role = Role.Button, onClickLabel = stringResource(R.string.game_page),
                onLongClickLabel = stringResource(R.string.options), onLongClick = { state.openMenu(game) }) { state.openGame(game) },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Box {
            GameCover(game, icon, focused, state.prefs.calm, Modifier.fillMaxWidth().aspectRatio(1f), hovered = hovered)
            if (state.favorite(game)) {
                val said = stringResource(R.string.favorite)
                Box(Modifier.align(Alignment.TopEnd).padding(canvas(OortTokens.Space.Line)).size(canvas(OortTokens.Space.PillInset)).background(OortTokens.Palette.Scrim.copy(alpha = OortTokens.Effect.DeepVeil), CircleShape)
                    .semantics { contentDescription = said }, contentAlignment = Alignment.Center) { OortGlyph(Glyph.Heart, Modifier.size(canvas(OortTokens.Space.Large)), tint = OortTokens.Palette.Ink) }
            }
        }
        Text(game.title, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
