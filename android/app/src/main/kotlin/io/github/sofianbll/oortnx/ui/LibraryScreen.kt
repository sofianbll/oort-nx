package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
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
        if (games.isEmpty()) {
            if (state.scanned) EmptyLibrary(state, Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(28.dp))
            else Text(stringResource(R.string.library_scanning), Modifier.padding(28.dp), style = MaterialTheme.typography.bodyLarge, color = Ink2)
            return@BoxWithConstraints
        }
        val columns = (maxWidth / 172.dp).toInt().coerceAtLeast(2)
        SideEffect { state.columns = columns }
        val grid = rememberLazyGridState()
        LaunchedEffect(state.libraryFocus, state.padMode) {
            if (!state.padMode) return@LaunchedEffect
            val info = grid.layoutInfo
            val seen = info.visibleItemsInfo.firstOrNull { it.index == state.libraryFocus }
            if (seen == null || seen.offset.y < 0 || seen.offset.y + seen.size.height > info.viewportEndOffset) grid.animateScrollToItem(state.libraryFocus)
        }
        LaunchedEffect(state.prefs.byName) { if (state.padMode) grid.animateScrollToItem(state.libraryFocus) else grid.scrollToItem(0) }
        Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
            PageTitle(stringResource(R.string.nav_library), null) { SortKey(state) }
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns),
                state = grid,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(bottom = 24.dp),
                modifier = Modifier.weight(1f),
            ) {
                itemsIndexed(games, key = { _, g -> g.packageName }) { index, game ->
                    GameTile(state, game, state.icons[game.packageName], focused = state.padMode && index == state.libraryFocus)
                }
            }
            Hints(state, listOf(
                HintKey.Confirm to R.string.game_page, HintKey.Options to R.string.options, HintKey.Sort to R.string.sort,
                HintKey.Tabs to R.string.hint_tabs, HintKey.Back to R.string.back,
            ))
        }
    }
}

@Composable
private fun SortKey(state: AppState) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconKey(Glyph.Sort, stringResource(R.string.sort)) { open = true }
        DropdownMenu(open, { open = false }, containerColor = PanelRaised, border = BorderStroke(1.dp, LineStrong)) {
            for ((byName, label) in listOf(false to R.string.sort_last, true to R.string.sort_name)) {
                DropdownMenuItem(
                    text = { Text(stringResource(label), style = MaterialTheme.typography.bodyLarge) },
                    onClick = { open = false; state.sort(byName) },
                    trailingIcon = { if (state.prefs.byName == byName) OortGlyph(Glyph.Check) },
                    modifier = Modifier.semantics { selected = state.prefs.byName == byName },
                )
            }
        }
    }
}

@Composable
private fun GameTile(state: AppState, game: Game, icon: ImageBitmap?, focused: Boolean) {
    Column(
        Modifier
            .fillMaxWidth()
            .combinedClickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClickLabel = stringResource(R.string.game_page),
                onLongClickLabel = stringResource(R.string.options), onLongClick = { state.openMenu(game) }) { state.openGame(game) },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        GameCover(game, icon, focused, state.prefs.calm, Modifier.fillMaxWidth().aspectRatio(1f))
        Text(game.title, Modifier.padding(horizontal = 6.dp), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, minLines = 2, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}
