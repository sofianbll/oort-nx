package io.github.sofianbll.oortnx.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.PointMode
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.Game

/** Selene's halftone: rows of dots, [rise] from 0 (none) to 1. */
fun DrawScope.halftone(rise: Float, color: Color) {
    if (rise <= 0.01f) return
    val pitch = OortTokens.Effect.DotPitch.dp.toPx()
    val points = ArrayList<Offset>()
    var y = pitch / 2
    while (y < size.height) {
        var x = pitch / 2
        while (x < size.width) { points.add(Offset(x, y)); x += pitch }
        y += pitch
    }
    drawPoints(points, PointMode.Points, color, OortTokens.Effect.DotRadius.dp.toPx() * 2f * rise, StrokeCap.Round)
}

/** The one key: solid for the main action, panel for the others. It sinks under the finger and lights under the controller. */
@Composable
fun OortKey(
    onClick: () -> Unit,
    calm: Boolean,
    modifier: Modifier = Modifier,
    solid: Boolean = false,
    focused: Boolean = false,
    round: Boolean = false,
    glyph: Glyph? = null,
    label: String? = null,
    description: String? = null,
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val rise by animateFloatAsState(if (focused || pressed) 1f else 0f, motion(calm, OortTokens.Motion.SlowMs), label = "dots")
    val sink by animateFloatAsState(if (pressed && !calm) OortTokens.Effect.PressScale else 1f, motion(calm, OortTokens.Motion.PressMs), label = "press")
    val shape: Shape = if (round) CircleShape else RoundedCornerShape(canvas(OortTokens.Radius.Dialog))
    val fill = if (solid) listOf(OortTokens.Palette.Focus, over(OortTokens.Palette.Focus, OortTokens.Palette.Glyph, OortTokens.Effect.SurfaceLineStrong)) else listOf(PanelRaised, PanelLow)
    val dots = if (solid) OortTokens.Palette.Glyph.copy(alpha = 0.55f) else OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.SurfaceLineStrong)
    val ring = if (focused) OortTokens.Palette.Focus else Color.Transparent
    // The ring stands off the key: a solid key is already white.
    Box(modifier.border(2.dp, ring, if (round) CircleShape else RoundedCornerShape(canvas(OortTokens.Radius.Dialog) + 5.dp)).padding(5.dp)) {
        Row(
            Modifier
                .then(if (round) Modifier else Modifier.fillMaxWidth())
                .graphicsLayer { scaleX = sink; scaleY = sink }
                .clip(shape)
                .background(Brush.verticalGradient(fill))
                .drawBehind { halftone(rise, dots) }
                .then(if (solid) Modifier else Modifier.border(1.dp, LineStrong, shape))
                .clickable(source, indication = null, role = Role.Button, onClick = onClick)
                .defaultMinSize(minWidth = 56.dp, minHeight = 56.dp)
                .padding(horizontal = if (round) 0.dp else 24.dp, vertical = if (round) 0.dp else 8.dp)
                .semantics { description?.let { contentDescription = it } },
            horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val tint = if (solid) OortTokens.Palette.OnFocus else OortTokens.Palette.Ink
            glyph?.let { OortGlyph(it, tint = tint, modifier = Modifier.size(22.dp)) }
            label?.let { Text(it, color = tint, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center) }
        }
    }
}

/** The panel lists and cards sit on. */
fun Modifier.oortPanel(shape: Shape): Modifier = clip(shape).background(Brush.verticalGradient(listOf(PanelHigh, PanelLow))).border(1.dp, Line, shape)

/** A game's cover: its icon, or its letter on the halftone. */
@Composable
fun GameCover(game: Game, icon: ImageBitmap?, focused: Boolean, calm: Boolean, modifier: Modifier = Modifier, radius: Dp = canvas(OortTokens.Radius.Modal)) {
    val shape = RoundedCornerShape(radius)
    val ring by animateFloatAsState(if (focused) 1f else 0f, motion(calm, if (focused) OortTokens.Motion.FocusInMs else OortTokens.Motion.FocusOutMs), label = "ring")
    Box(modifier.border(2.dp, OortTokens.Palette.Focus.copy(alpha = ring), RoundedCornerShape(radius + 4.dp)).padding(4.dp)) {
        if (icon != null) {
            Image(icon, contentDescription = null, modifier = Modifier.fillMaxSize().clip(shape), contentScale = ContentScale.Crop)
        } else {
            Box(
                Modifier.fillMaxSize().clip(shape).background(Brush.verticalGradient(listOf(PanelRaised, PanelLow)))
                    .drawBehind { halftone(1f, OortTokens.Palette.Glyph.copy(alpha = 0.12f)) }.border(1.dp, Line, shape),
                contentAlignment = Alignment.Center,
            ) {
                Text(game.title.take(1).uppercase(), style = MaterialTheme.typography.displayMedium, fontWeight = FontWeight.SemiBold, modifier = Modifier.clearAndSetSemantics { })
            }
        }
    }
}

/** A dot that says the game is ready; the words beside it say it too. */
@Composable
fun StateLine(text: String, modifier: Modifier = Modifier) {
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
        Canvas(Modifier.size(9.dp)) { drawCircle(OortTokens.Status.StatusOk) }
        Text(text, style = MaterialTheme.typography.bodyLarge, color = Ink2)
    }
}

/** The page's name, and the way back when there is one. */
@Composable
fun PageTitle(title: String, onBack: (() -> Unit)?, modifier: Modifier = Modifier, actions: @Composable () -> Unit = {}) {
    Row(modifier.fillMaxWidth().padding(top = 8.dp, bottom = 8.dp).sizeIn(minHeight = 56.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (onBack != null) IconKey(Glyph.Back, stringResource(R.string.back), onBack)
        Text(title, Modifier.weight(1f).heading(), style = if (onBack == null) MaterialTheme.typography.headlineLarge else MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
        actions()
    }
}

@Composable
fun IconKey(glyph: Glyph, description: String, onClick: () -> Unit) {
    Box(
        Modifier.size(48.dp).clip(CircleShape).background(PanelRaised).clickable(role = Role.Button, onClick = onClick).semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) { OortGlyph(glyph, tint = OortTokens.Palette.Ink, modifier = Modifier.size(22.dp)) }
}

/** The controller's keys for what can be done here. Touch hides them. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun Hints(state: AppState, hints: List<Pair<String, String>>, modifier: Modifier = Modifier) {
    if (!state.padMode) return
    FlowRow(
        modifier.fillMaxWidth().padding(vertical = 8.dp).clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(20.dp, Alignment.End), verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        for ((key, label) in hints) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.sizeIn(minWidth = 22.dp, minHeight = 22.dp).background(OortTokens.Palette.Ink, RoundedCornerShape(11.dp)).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
                    Text(key, color = OortTokens.Palette.OnFocus, style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold)
                }
                Text(label, color = Ink2, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

/** The button that confirms, and the one that goes back, on the controller in hand. */
val AppState.confirmKey: String get() = if (prefs.swapAB) "B" else "A"
val AppState.backKey: String get() = if (prefs.swapAB) "A" else "B"

@Composable
fun EmptyLibrary(state: AppState, modifier: Modifier = Modifier) {
    androidx.compose.foundation.layout.Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.Bottom)) {
        Text(stringResource(R.string.empty_title), Modifier.heading(), style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
        Text(stringResource(R.string.empty_body), style = MaterialTheme.typography.bodyLarge, color = Ink2, modifier = Modifier.sizeIn(maxWidth = 520.dp))
        OortKey({ state.rescan() }, state.prefs.calm, Modifier.sizeIn(maxWidth = 420.dp), solid = true, focused = state.padMode, glyph = Glyph.Refresh, label = stringResource(R.string.empty_rescan))
    }
}
