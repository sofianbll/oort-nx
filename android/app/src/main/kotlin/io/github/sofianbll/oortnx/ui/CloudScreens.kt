package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.CloudGame
import io.github.sofianbll.oortnx.core.CloudState
import io.github.sofianbll.oortnx.core.DownloadCloud

/** This device's games, or the cloud's: only when the module is on and has a code. */
@Composable
fun LibraryFilter(state: AppState) {
    if (state.cloud?.hasFilter != true) return
    val ring = if (state.padMode && state.onFilter) OortTokens.Palette.Focus else Color.Transparent
    Row(Modifier.padding(bottom = OortTokens.Space.Compact.dp).border(OortTokens.Space.FocusStroke.dp, ring, CircleShape).padding(OortTokens.Space.Hairline.dp).clip(CircleShape).background(PanelLow).border(OortTokens.Space.ThinStroke.dp, LineStrong, CircleShape).padding(OortTokens.Space.Hairline.dp).selectableGroup()) {
        for ((cloud, label) in listOf(false to R.string.cloud_here, true to R.string.cloud_filter)) {
            val on = state.inCloud == cloud
            Box(
                Modifier.clip(CircleShape).background(if (on) OortTokens.Palette.Focus else Color.Transparent)
                    .selectable(on, role = Role.Tab) { state.showCloud(cloud) }.heightIn(min = OortTokens.Space.Group.dp).padding(horizontal = OortTokens.Space.Control.dp),
                contentAlignment = Alignment.Center,
            ) { Text(stringResource(label), color = if (on) OortTokens.Palette.OnFocus else OortTokens.Palette.Ink, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold) }
        }
    }
}

/** The library's cloud side: what runs here, then what does not and why. */
@Composable
fun CloudLibrary(state: AppState, cloud: CloudState) {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val columns = (maxWidth / OortMeasure.Tile).toInt().coerceAtLeast(2)
        SideEffect { state.columns = columns }
        val grid = rememberLazyGridState()
        LaunchedEffect(state.libraryFocus, state.padMode) { if (state.padMode) grid.animateScrollToItem((state.libraryFocus + 1).coerceAtMost(cloud.games.size)) }
        LaunchedEffect(Unit) { if (!cloud.listed) state.cloudCall("look") }
        Column(Modifier.fillMaxSize().padding(horizontal = OortTokens.Space.Panel.dp)) {
            PageTitle(stringResource(R.string.nav_library), null) { IconKey(Glyph.Refresh, stringResource(R.string.cloud_again)) { state.cloudCall("look") } }
            LibraryFilter(state)
            LazyVerticalGrid(
                columns = GridCells.Fixed(columns), state = grid, horizontalArrangement = Arrangement.spacedBy(OortTokens.Space.Compact.dp), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.Medium.dp),
                contentPadding = PaddingValues(bottom = OortTokens.Space.Large.dp), modifier = Modifier.weight(1f),
            ) {
                item(span = { GridItemSpan(maxLineSpan) }) { CloudStatus(state, cloud) }
                itemsIndexed(cloud.games, key = { _, g -> g.title }) { index, game -> CloudTile(state, cloud, game, focused = state.padMode && !state.onFilter && index == state.libraryFocus) }
                if (cloud.others.isNotEmpty()) item(span = { GridItemSpan(maxLineSpan) }) { CloudOthers(cloud) }
            }
            Hints(state, listOf(state.confirmKey to stringResource(R.string.game_page), state.backKey to stringResource(R.string.back)))
        }
    }
}

@Composable
private fun CloudStatus(state: AppState, cloud: CloudState) {
    Column(Modifier.widthIn(max = OortMeasure.List), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.Small.dp)) {
        Text(listOfNotNull(stringResource(R.string.cloud_free, size(cloud.free)), if (cloud.looking) stringResource(R.string.cloud_looking) else null).joinToString("  ·  "),
            style = MaterialTheme.typography.bodyLarge, color = Ink2)
        val (words, key, run) = when {
            cloud.stage == "signIn" || cloud.problem == "signInNeeded" -> Triple(R.string.cloud_error_sign_in, R.string.cloud_sign_in_again) { state.cloudStep("signIn") }
            cloud.problem != null -> Triple(errorWords(cloud.problem), R.string.cloud_try_again) { state.cloudCall("look") }
            cloud.listed && cloud.games.isEmpty() -> Triple(R.string.cloud_empty, R.string.cloud_again) { state.cloudCall("look") }
            else -> return@Column
        }
        Column(Modifier.fillMaxWidth().oortPanel(RoundedCornerShape(canvas(OortTokens.Radius.Dialog))).padding(OortTokens.Space.Medium.dp), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.FieldInset.dp)) {
            Text(stringResource(words), style = MaterialTheme.typography.bodyLarge)
            OortKey(run, state.prefs.calm, Modifier.widthIn(max = OortMeasure.Key), glyph = Glyph.Refresh, label = stringResource(key))
        }
    }
}

@Composable
private fun CloudTile(state: AppState, cloud: CloudState, game: CloudGame, focused: Boolean) {
    val words = cloudWords(cloud, game)
    val facts = game.version + " · " + size(game.bytes)
    Column(
        Modifier.fillMaxWidth().clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button, onClickLabel = stringResource(R.string.game_page)) { state.openCloudGame(game) },
        verticalArrangement = Arrangement.spacedBy(OortTokens.Space.FocusStroke.dp),
    ) {
        CloudCover(state, cloud, game, focused, Modifier.fillMaxWidth().aspectRatio(1f))
        Text(game.name, Modifier.padding(horizontal = OortTokens.Space.Tight.dp), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Text(facts, Modifier.padding(horizontal = OortTokens.Space.Tight.dp), style = MaterialTheme.typography.bodyMedium, color = Ink2)
        Text(words, Modifier.padding(horizontal = OortTokens.Space.Tight.dp), style = MaterialTheme.typography.bodyMedium, color = Ink2)
    }
}

/** The game's picture if it is here, else its letter on the halftone, filling with the Oort cloud while it comes. */
@Composable
fun CloudCover(state: AppState, cloud: CloudState, game: CloudGame, focused: Boolean, modifier: Modifier) {
    val radius = canvas(OortTokens.Radius.Modal)
    val shape = RoundedCornerShape(radius)
    val level = game.job?.takeIf { it.state != "ready" }?.let { if (game.bytes > 0) it.received.toDouble() / game.bytes else 0.0 }
    val moving = game.job?.state == "running" && cloud.network != "none"
    val calm = state.prefs.calm
    var now by remember { mutableLongStateOf(System.nanoTime()) }
    val track = remember(game.title, level == null, calm) { level?.let { DownloadCloud.Track(it, moving, System.nanoTime() / 1e9, calm) } }
    LaunchedEffect(track, level, moving) {
        track?.receive(level ?: 0.0, moving, System.nanoTime() / 1e9)
        // At rest nothing asks for a frame.
        while (track != null && (System.nanoTime() / 1e9 < track.end)) withFrameNanos { now = System.nanoTime() }
        now = System.nanoTime()
    }
    val icon = game.packageName?.let { state.icons[it] }
    val seed = remember(game.title) { game.title.toULongOrNull(16)?.toLong() ?: 0L }
    Box(modifier.border(OortTokens.Space.FocusStroke.dp, OortTokens.Palette.Focus.copy(alpha = if (focused) 1f else 0f), RoundedCornerShape(radius + OortTokens.Space.Hairline.dp)).padding(OortTokens.Space.Hairline.dp)) {
        val face: @Composable (Float) -> Unit = { alpha ->
            Box(
                Modifier.fillMaxSize().clip(shape).background(Brush.verticalGradient(listOf(PanelRaised, PanelLow)))
                    .drawBehind { halftone(1f, OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.SurfaceLine * alpha)) }.border(OortTokens.Space.ThinStroke.dp, Line, shape),
                contentAlignment = Alignment.Center,
            ) {
                if (icon != null) androidx.compose.foundation.Image(icon, null, Modifier.fillMaxSize(), contentScale = androidx.compose.ui.layout.ContentScale.Crop, alpha = alpha)
                else Text(game.name.take(1).uppercase(), Modifier.clearAndSetSemantics { }, color = OortTokens.Palette.Ink.copy(alpha = alpha), style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.SemiBold)
            }
        }
        face(if (track != null) OortTokens.Effect.PanelVeil else 1f)
        if (track != null) {
            Canvas(Modifier.fillMaxSize().clip(shape)) {
                val sample = track.sample(now / 1e9)
                val w = size.width.toDouble()
                val h = size.height.toDouble()
                val paint = { drawRect(Brush.verticalGradient(listOf(OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.PanelVeil), OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.SurfaceLineStrong)))); halftone(1f, OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.PanelVeil)) }
                if (sample.bands.isNotEmpty()) {
                    var bottom = 1.0
                    for (band in sample.bands) {
                        clipRect(0f, ((1 - band.level) * h).toFloat(), size.width, (bottom * h).toFloat()) { drawRect(OortTokens.Palette.Glyph.copy(alpha = (OortTokens.Effect.SurfaceLineStrong * band.opacity).toFloat())); halftone(1f, OortTokens.Palette.Glyph.copy(alpha = (OortTokens.Effect.PanelVeil * band.opacity).toFloat())) }
                        bottom = 1 - band.level
                    }
                } else {
                    val curve = Path()
                    for (i in 0..32) { val x = w * i / 32; val y = sample.surface.y(x, w, h).toFloat(); if (i == 0) curve.moveTo(x.toFloat(), y) else curve.lineTo(x.toFloat(), y) }
                    val full = Path().apply { addPath(curve); lineTo(size.width, size.height); lineTo(0f, size.height); close() }
                    clipPath(full) { paint() }
                    if (sample.surface.activity > 0) {
                        drawPath(curve, OortTokens.Palette.Focus.copy(alpha = DownloadCloud.lineOpacity(sample.surface).toFloat()), style = Stroke(OortTokens.Space.ThinStroke.dp.toPx()))
                        for (dot in DownloadCloud.dots(sample.surface, seed, w, h)) if (dot.opacity > 0) {
                            val at = Offset(dot.x.toFloat(), dot.y.toFloat())
                            val reach = (dot.radius * DownloadCloud.SPRITE_REACH).toFloat()
                            drawCircle(Brush.radialGradient(listOf((if (dot.accent) OortTokens.Palette.Glyph else OortTokens.Palette.Ink).copy(alpha = (OortTokens.Effect.PanelVeil * dot.opacity).toFloat()), Color.Transparent), at, reach), reach, at)
                            drawCircle(OortTokens.Palette.Focus.copy(alpha = dot.opacity.toFloat()), dot.radius.toFloat(), at)
                        }
                    }
                }
            }
        }
        val mark = when (game.job?.state) {
            "running" -> Glyph.Down
            "waiting" -> Glyph.Wait
            "paused" -> Glyph.Pause
            "failed" -> Glyph.Info
            "ready" -> Glyph.Check
            else -> if (game.installed) null else if (game.here != null) Glyph.Up else Glyph.Cloud
        }
        mark?.let { Box(Modifier.align(Alignment.TopEnd).padding(OortTokens.Space.Tight.dp).size(OortTokens.Space.RowLeading.dp).clip(CircleShape).background(OortTokens.Palette.Scrim.copy(alpha = OortTokens.Effect.SearchVeil)), contentAlignment = Alignment.Center) { OortGlyph(it, Modifier.size(OortTokens.Space.Medium.dp), OortTokens.Palette.Ink) } }
    }
}

@Composable
private fun CloudOthers(cloud: CloudState) {
    Column(Modifier.widthIn(max = OortMeasure.List).padding(top = OortTokens.Space.Small.dp), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.FieldInset.dp)) {
        Text(stringResource(R.string.cloud_not_here), Modifier.heading(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        Column(Modifier.fillMaxWidth().oortPanel(RoundedCornerShape(canvas(OortTokens.Radius.Dialog)))) {
            cloud.others.forEachIndexed { index, other ->
                if (index > 0) Spacer(Modifier.padding(horizontal = OortTokens.Space.Medium.dp).fillMaxWidth().height(OortTokens.Space.ThinStroke.dp).background(Line))
                Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { }.padding(horizontal = OortTokens.Space.Medium.dp, vertical = OortTokens.Space.Small.dp), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.FocusStroke.dp)) {
                    Text(other.name, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium)
                    Text(stringResource(reasonWords(other.reason)), style = MaterialTheme.typography.bodyMedium, color = Ink2)
                }
            }
        }
    }
}

/** One game of the cloud: what it is, what it needs, and the one thing to do now. */
@Composable
fun CloudGameScreen(state: AppState, cloud: CloudState, game: CloudGame) {
    val sections = state.sections()
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val wide = maxWidth > maxHeight && maxWidth >= OortMeasure.Wide
        val short = maxHeight < OortMeasure.Short
        val side = if (wide && short) OortMeasure.ShortCover else minOf(maxWidth / 2, maxHeight / 3, OortMeasure.Cover)
        val header: @Composable () -> Unit = {
            Column(verticalArrangement = Arrangement.spacedBy(OortTokens.Space.Small.dp)) {
                CloudCover(state, cloud, game, false, Modifier.size(side))
                Text(game.name, Modifier.heading(), style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                val words = cloudWords(cloud, game)
                Text(words, Modifier.semantics { stateDescription = words }, style = MaterialTheme.typography.bodyLarge, color = Ink2)
            }
        }
        if (wide) {
            Row(Modifier.fillMaxSize().padding(horizontal = OortTokens.Space.Large.dp), horizontalArrangement = Arrangement.spacedBy(OortTokens.Space.Large.dp)) {
                Column(Modifier.weight(OortMeasure.SideShare).widthIn(max = OortMeasure.Side).fillMaxHeight()) {
                    PageTitle(stringResource(R.string.game_page), { state.onBack() })
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) { header() }
                    CloudKey(state, cloud, game, Modifier.padding(vertical = OortTokens.Space.Compact.dp), OortMeasure.WideKey)
                }
                Column(Modifier.weight(1 - OortMeasure.SideShare).fillMaxHeight()) {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).widthIn(max = OortMeasure.List).padding(vertical = OortTokens.Space.Large.dp)) { OortList(state, sections) }
                    PageHints(state)
                }
            }
        } else {
            Column(Modifier.fillMaxSize()) {
                PageTitle(stringResource(R.string.game_page), { state.onBack() }, Modifier.padding(horizontal = OortTokens.Space.Panel.dp))
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = OortTokens.Space.Panel.dp, end = OortTokens.Space.Panel.dp, bottom = OortTokens.Space.DialogInset.dp), verticalArrangement = Arrangement.spacedBy(OortTokens.Space.Large.dp)) {
                    header()
                    OortList(state, sections, Modifier.widthIn(max = OortMeasure.List))
                }
                Column(Modifier.fillMaxWidth().background(OortTokens.Palette.Scrim.copy(alpha = OortTokens.Effect.CloudBadgeOpacity)).padding(horizontal = OortTokens.Space.Medium.dp).padding(bottom = OortTokens.Space.Compact.dp)) {
                    CloudKey(state, cloud, game, Modifier, OortMeasure.WideKey)
                    PageHints(state)
                }
            }
        }
    }
}

@Composable
private fun CloudKey(state: AppState, cloud: CloudState, game: CloudGame, modifier: Modifier, max: Dp) {
    val action = state.cloudAction(cloud, game)
    OortKey(action.run, state.prefs.calm, modifier.widthIn(max = max).fillMaxWidth(), solid = true,
        focused = state.padMode && state.focusedRow() == AppState.PLAY, glyph = action.glyph, label = stringResource(action.label))
}

/** The code as text, typed or pasted. */
@Composable
fun CodeDialog(state: AppState) {
    if (!state.pasting) return
    var text by remember { mutableStateOf("") }
    val label = stringResource(R.string.cloud_code_field)
    AlertDialog(
        onDismissRequest = { state.pasting = false },
        containerColor = PanelRaised,
        title = { Text(stringResource(R.string.cloud_paste)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(OortTokens.Space.Small.dp)) {
                Text(stringResource(R.string.cloud_paste_note), style = MaterialTheme.typography.bodyMedium, color = Ink2)
                OutlinedTextField(text, { text = it }, Modifier.fillMaxWidth().semantics { contentDescription = label }, minLines = 3, maxLines = 6,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Password))
            }
        },
        confirmButton = { TextButton({ state.useCode(text) }, enabled = text.isNotBlank()) { Text(stringResource(R.string.cloud_use_code)) } },
        dismissButton = { TextButton({ state.pasting = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

// ---- words ------------------------------------------------------------------------------------------------

@Composable
fun size(bytes: Long): String = android.text.format.Formatter.formatShortFileSize(androidx.compose.ui.platform.LocalContext.current, bytes)

@Composable
fun cloudWords(cloud: CloudState, game: CloudGame): String {
    if (cloud.installing == game.title) return stringResource(R.string.cloud_installing)
    val job = game.job
    return when (job?.state) {
        "running" -> when {
            cloud.network == "none" -> stringResource(R.string.cloud_error_offline)
            cloud.network == "metered" && cloud.wifiOnly -> stringResource(R.string.cloud_error_wifi)
            else -> stringResource(R.string.cloud_share, if (game.bytes > 0) (job.received * 100 / game.bytes).toInt() else 0, size(job.received), size(game.bytes))
        }
        "waiting" -> job.reason?.let { stringResource(errorWords(it)) } ?: stringResource(R.string.cloud_waiting)
        "paused" -> stringResource(R.string.cloud_paused)
        "failed" -> if (job.reason == "noSpace" && job.needed != null) stringResource(R.string.cloud_error_room, size(job.needed), size(cloud.free)) else stringResource(errorWords(job.reason.orEmpty()))
        "ready" -> stringResource(R.string.cloud_ready)
        else -> stringResource(if (game.installed) R.string.cloud_installed else if (game.here != null) R.string.cloud_update else R.string.cloud_on_drive)
    }
}

fun errorWords(code: String): Int = when (code) {
    "offline" -> R.string.cloud_error_offline
    "networkNotAllowed" -> R.string.cloud_error_wifi
    "signInNeeded" -> R.string.cloud_error_sign_in
    "accessDenied" -> R.string.cloud_error_refused
    "notFound" -> R.string.cloud_error_gone
    "quotaExceeded" -> R.string.cloud_error_quota
    "busy", "server", "interrupted" -> R.string.cloud_error_busy
    "noSpace" -> R.string.cloud_error_space
    "wrongDigest", "wrongSize", "unsigned", "invalidManifest", "unsafeName" -> R.string.cloud_error_file
    "filesMissing" -> R.string.cloud_reason_files
    "localFile" -> R.string.cloud_error_local
    else -> R.string.cloud_error_other
}

fun reasonWords(reason: String): Int = when (reason) {
    "notPrepared" -> R.string.cloud_reason_mac
    "system" -> R.string.cloud_reason_system
    "graphics" -> R.string.cloud_reason_graphics
    "launcher" -> R.string.cloud_reason_launcher
    "filesMissing" -> R.string.cloud_reason_files
    "unsigned" -> R.string.cloud_reason_unsigned
    else -> R.string.cloud_reason_damaged
}
