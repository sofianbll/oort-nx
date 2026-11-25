package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R
import io.github.sofianbll.oortnx.core.PadMonitor
import io.github.sofianbll.oortnx.core.PadShape
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlinx.coroutines.delay

/** Each button lights where it is on the controller. Holding A or B closes, so every button can be tried. */
@Composable
fun PadTestScreen(state: AppState) {
    val pad = state.pad
    val closing = pad.held.closing
    DisposableEffect(Unit) { onDispose { pad.reset() } }
    LaunchedEffect(closing) { if (closing) { delay(1_200); state.onBack() } }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        PageTitle(stringResource(R.string.controllers_test), { state.onBack() })
        BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
            val wide = minOf(maxWidth, 560.dp, (maxHeight - 120.dp).coerceAtLeast(150.dp) / 0.72f)
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp, Alignment.CenterVertically), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    pad.lastKey?.let { stringResource(R.string.controllers_last, state.family.mark(state.family.printed(it))) } ?: stringResource(R.string.controllers_press),
                    style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center,
                )
                PadView(pad.held, Modifier.width(wide).oortPanel(RoundedCornerShape(canvas(OortTokens.Radius.Dialog))).padding(20.dp))
                Text(stringResource(R.string.controllers_hold, state.keyName(HintKey.Confirm), state.keyName(HintKey.Back)), style = MaterialTheme.typography.bodyMedium, color = Ink2, textAlign = TextAlign.Center)
            }
        }
    }
}

/** The pad in the player's hands, in the cloud's dots: what is pressed lights up, the sticks lean. */
@Composable
private fun PadView(held: PadMonitor.Held, modifier: Modifier = Modifier) {
    Canvas(modifier.aspectRatio(1f / 0.72f)) {
        val unit = size.width / 2
        val zoom = size.width / 420f
        val middle = Offset(size.width / 2, size.height * 0.54f)
        fun dot(x: Float, y: Float, radius: Float, color: Color, alpha: Float) =
            drawCircle(color.copy(alpha = alpha.coerceIn(0f, 1f)), radius * zoom, Offset(middle.x + x * unit, middle.y + y * unit))
        val glyph = OortTokens.Palette.Glyph
        for (cell in PadShape.cells) {
            val x = cell.x.toFloat()
            val y = cell.y.toFloat()
            val edge = cell.edge.toFloat()
            val place = cell.part
            if (place != null) {
                val lit = held.press(place)
                if (lit > 0.08f) dot(x, y, 2.4f + lit * 3.2f * (1 - edge * 0.4f), OortTokens.Palette.Focus, 0.35f + lit * 0.65f)
                else if (edge > 0.66f) dot(x, y, 2.2f, glyph, 0.9f)
            } else {
                val shade = 0.4f + 0.5f * max(0f, 0.5f + x * 0.5f - y * 0.4f)
                dot(x, y, 1.5f + shade * 2.2f, glyph, 0.25f + shade * 0.6f)
            }
        }
        for ((part, sx, sy) in listOf(Triple(PadShape.parts[0], held.leftX, held.leftY), Triple(PadShape.parts[1], held.rightX, held.rightY))) {
            for (step in 0 until 16) {
                val a = (step / 16f * 2 * PI).toFloat()
                dot(part.x.toFloat() + sx * 0.05f + cos(a) * 0.065f, part.y.toFloat() + sy * 0.05f + sin(a) * 0.065f, 2.3f, glyph, 1f)
            }
        }
        val shoulders = held.shoulders
        for ((index, at) in listOf(-1.0 to 0.0, -1.0 to 1.0, 1.0 to 0.0, 1.0 to 1.0).withIndex()) {
            val lit = shoulders[index]
            for (p in PadShape.shoulder(at.first, at.second)) {
                dot(p.x.toFloat(), p.y.toFloat(), 2f + lit * 2.6f, if (lit > 0.04f) OortTokens.Palette.Focus else glyph, 0.5f - at.second.toFloat() * 0.12f + lit * 0.5f)
            }
        }
    }
}
