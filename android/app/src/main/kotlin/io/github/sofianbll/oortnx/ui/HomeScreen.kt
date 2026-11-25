package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game
import kotlin.math.absoluteValue

/** À la une: the last games started, the chosen one large, and Play under the thumb. */
@Composable
fun HomeScreen(state: AppState) {
    val games = state.recent
    val game = state.selected
    BoxWithConstraints(Modifier.fillMaxSize()) {
        when {
            game == null -> if (state.scanned) {
                EmptyLibrary(state, Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = maxHeight).padding(28.dp))
            }
            maxHeight > maxWidth -> Upright(state, games, game, maxWidth, maxHeight)
            else -> Wide(state, games, game, maxWidth, maxHeight)
        }
    }
}

private val MARGIN = 28.dp

@Composable
private fun Upright(state: AppState, games: List<Game>, game: Game, width: Dp, height: Dp) {
    // The next cover shows its edge: that is how the swipe is learnt.
    // It gives way on a short screen or with large text: Play stays in view.
    val text = (200 + 105 * LocalDensity.current.fontScale).dp + if (state.padMode) 44.dp else 0.dp
    val side = minOf(width - 100.dp, height * 0.56f, height - text).coerceAtLeast(130.dp)
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).heightIn(min = height).padding(vertical = 16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.Bottom),
    ) {
        Covers(state, games, game, side, width)
        Places(games.size, games.indexOf(game), Modifier.align(Alignment.CenterHorizontally))
        Heading(state, game, Modifier.padding(horizontal = MARGIN))
        Column(Modifier.padding(horizontal = MARGIN - 5.dp).widthIn(max = 560.dp)) {
            Keys(state, game, Modifier.fillMaxWidth())
            HomeHints(state)
        }
    }
}

/** A phone on its side, a tablet: the games along the top, the chosen cover as tall as the window allows. */
@Composable
private fun Wide(state: AppState, games: List<Game>, game: Game, width: Dp, height: Dp) {
    val large = height >= 600.dp
    val gutter = if (large) 48.dp else 24.dp
    val side = minOf(height * 0.74f, width * 0.38f)
    Row(Modifier.fillMaxSize().padding(end = gutter), horizontalArrangement = Arrangement.spacedBy(gutter), verticalAlignment = Alignment.CenterVertically) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).heightIn(min = height).padding(vertical = if (large) 48.dp else 8.dp),
            verticalArrangement = Arrangement.SpaceBetween,
        ) {
            Rail(state, games, game, if (large) 124.dp else 84.dp, gutter)
            Column(Modifier.padding(start = gutter, top = 12.dp), verticalArrangement = Arrangement.spacedBy(if (large) 24.dp else 12.dp)) {
                Heading(state, game)
                Keys(state, game, Modifier.widthIn(max = 460.dp).fillMaxWidth())
                HomeHints(state)
            }
        }
        GameCover(game, state.icons[game.packageName], focused = false, calm = state.prefs.calm, modifier = Modifier.size(side), radius = canvas(OortTokens.Radius.Dialog))
    }
}

@Composable
private fun HomeHints(state: AppState, modifier: Modifier = Modifier) {
    val first = when (state.homeTarget) {
        HomeTarget.Cover, HomeTarget.Play -> stringResource(R.string.detail_play)
        HomeTarget.Page -> stringResource(R.string.game_page)
        HomeTarget.Android -> stringResource(R.string.detail_info)
    }
    Hints(state, listOfNotNull(
        state.confirmKey to first, if (state.homeTarget == HomeTarget.Page) null else "X" to stringResource(R.string.game_page),
        "Y" to stringResource(R.string.nav_controllers), "R1" to stringResource(R.string.nav_library),
    ), modifier)
}

@Composable
private fun Heading(state: AppState, game: Game, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(game.title, Modifier.heading(), style = if (game.title.length > 28) MaterialTheme.typography.headlineSmall else MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        StateLine(state.lastStart(game).text())
        if (game.versionName.isNotEmpty()) Text(stringResource(R.string.detail_version, game.versionName), style = MaterialTheme.typography.bodyMedium, color = Ink2)
    }
}

@Composable
private fun Keys(state: AppState, game: Game, modifier: Modifier = Modifier) {
    val calm = state.prefs.calm
    fun lit(target: HomeTarget) = state.padMode && state.homeTarget == target
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        OortKey({ state.play(game) }, calm, Modifier.weight(1f), solid = true, focused = lit(HomeTarget.Play), glyph = Glyph.Play, label = stringResource(R.string.detail_play))
        OortKey({ state.openGame(game) }, calm, focused = lit(HomeTarget.Page), round = true, glyph = Glyph.Info, description = stringResource(R.string.game_page))
        OortKey({ state.androidPage(game) }, calm, focused = lit(HomeTarget.Android), round = true, glyph = Glyph.Device, description = stringResource(R.string.detail_info))
    }
}

/** The covers under the thumb: a swipe changes the game, a tap on the middle one opens its page. */
@Composable
private fun Covers(state: AppState, games: List<Game>, game: Game, side: Dp, width: Dp) {
    val here = games.indexOf(game).coerceAtLeast(0)
    val pager = rememberPagerState(initialPage = here) { games.size }
    val now = rememberUpdatedState(games)
    val calm = state.prefs.calm
    LaunchedEffect(here, games.size) {
        if (pager.currentPage != here) if (calm) pager.scrollToPage(here) else pager.animateScrollToPage(here)
    }
    // Only a finger chooses here; the controller has already chosen.
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.collect { page -> if (!state.padMode) now.value.getOrNull(page)?.let { if (pager.currentPage == page) state.select(it) } }
    }
    HorizontalPager(
        state = pager,
        key = { games.getOrNull(it)?.packageName ?: it },
        pageSize = PageSize.Fixed(side),
        contentPadding = PaddingValues(horizontal = (width - side) / 2),
        pageSpacing = 12.dp,
        beyondViewportPageCount = 1,
    ) { index ->
        val item = games.getOrNull(index) ?: return@HorizontalPager
        val selected = item.packageName == game.packageName
        val opens = stringResource(R.string.game_page)
        GameCover(
            item, state.icons[item.packageName],
            focused = selected && state.padMode && state.homeTarget == HomeTarget.Cover,
            calm = calm,
            radius = canvas(OortTokens.Radius.Dialog),
            modifier = Modifier
                .size(side)
                .graphicsLayer {
                    val off = (pager.currentPage - index + pager.currentPageOffsetFraction).absoluteValue.coerceIn(0f, 1f)
                    if (!calm) { scaleX = 1f - 0.1f * off; scaleY = scaleX }
                    alpha = 1f - 0.45f * off
                }
                .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab, onClickLabel = if (selected) opens else null) {
                    if (selected) state.openGame(item) else state.select(item)
                }
                .semantics { contentDescription = item.title; this.selected = selected },
        )
    }
}

/** Where the cover is among the games, in the mark's dots. */
@Composable
private fun Places(count: Int, here: Int, modifier: Modifier = Modifier) {
    if (count !in 2..14) return
    Canvas(modifier.size((count * 14).dp, 10.dp)) {
        for (i in 0 until count) {
            val on = i == here
            drawCircle(if (on) OortTokens.Palette.Focus else OortTokens.Palette.Glyph.copy(alpha = 0.4f), (if (on) 4.dp else 2.5.dp).toPx(), Offset((i * 14 + 7).dp.toPx(), size.height / 2))
        }
    }
}

@Composable
private fun Rail(state: AppState, games: List<Game>, game: Game, tile: Dp, gutter: Dp) {
    val list = rememberLazyListState()
    val here = games.indexOf(game).coerceAtLeast(0)
    LaunchedEffect(here) {
        val seen = list.layoutInfo.visibleItemsInfo.firstOrNull { it.index == here }
        if (seen == null || seen.offset < 0 || seen.offset + seen.size > list.layoutInfo.viewportEndOffset) list.animateScrollToItem(here)
    }
    val more = list.canScrollForward
    LazyRow(
        // The last cover fades where the row goes on.
        Modifier.graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
            drawContent()
            if (more) drawRect(Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = size.width - 56.dp.toPx(), endX = size.width), blendMode = BlendMode.DstIn)
        },
        state = list, horizontalArrangement = Arrangement.spacedBy(8.dp), contentPadding = PaddingValues(horizontal = gutter - 4.dp)) {
        itemsIndexed(games, key = { _, g -> g.packageName }) { _, item ->
            val selected = item.packageName == game.packageName
            GameCover(
                item, state.icons[item.packageName],
                focused = selected && (!state.padMode || state.homeTarget == HomeTarget.Cover),
                calm = state.prefs.calm,
                radius = canvas(OortTokens.Radius.Card),
                modifier = Modifier.size(tile)
                    .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Tab) { if (selected) state.openGame(item) else state.select(item) }
                    .semantics { contentDescription = item.title; this.selected = selected },
            )
        }
    }
}
