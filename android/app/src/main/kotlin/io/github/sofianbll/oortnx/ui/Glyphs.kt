package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

enum class Glyph { Library, Controllers, Settings, Play }

/** Icons drawn in the charter's dots, on a 24-unit grid. They carry no meaning alone: the label always sits beside them. */
@Composable
fun OortGlyph(glyph: Glyph, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) {
    Canvas(modifier.size(24.dp)) {
        val u = size.minDimension / 24f
        fun dot(x: Float, y: Float, r: Float) = drawCircle(tint, radius = r * u, center = Offset(x * u, y * u))
        when (glyph) {
            Glyph.Library -> for (row in 0..2) for (col in 0..2) dot(5f + col * 7f, 5f + row * 7f, 1.9f)
            Glyph.Controllers -> {
                for (i in 0 until 14) { // a ring for each hand
                    val a = (i / 14f * 2 * PI).toFloat()
                    dot(7.5f + 4.8f * cos(a), 12f + 4.8f * sin(a), 1.1f)
                    dot(16.5f + 4.8f * cos(a), 12f + 4.8f * sin(a), 1.1f)
                }
            }
            Glyph.Settings -> {
                dot(12f, 12f, 2.2f)
                for (i in 0 until 10) {
                    val a = (i / 10f * 2 * PI).toFloat()
                    dot(12f + 8f * cos(a), 12f + 8f * sin(a), 1.4f)
                }
            }
            Glyph.Play -> drawPath(
                Path().apply { moveTo(7f * u, 4.5f * u); lineTo(20f * u, 12f * u); lineTo(7f * u, 19.5f * u); close() },
                tint,
            )
        }
    }
}
