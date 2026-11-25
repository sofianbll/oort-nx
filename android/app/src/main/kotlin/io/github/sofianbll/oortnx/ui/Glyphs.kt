package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/** Line glyphs have [path], on a 24-unit grid with one stroke; the four places of the app are drawn in the charter's dots. */
enum class Glyph(val path: String? = null, val filled: Boolean = false, val stroke: Float = 1.8f) {
    Home, Library, Controllers, Settings,
    Play("M7.5 5.2v13.6a.8.8 0 0 0 1.2.7l10.6-6.8a.8.8 0 0 0 0-1.4L8.7 4.5a.8.8 0 0 0-1.2.7z", filled = true),
    Info("M12 11.2v7M12 6v.1", stroke = 3f),
    Sliders("M3 7h9M18 7h3M3 17h3M12 17h9M15 7m-3 0a3 3 0 1 0 6 0a3 3 0 1 0-6 0M9 17m-3 0a3 3 0 1 0 6 0a3 3 0 1 0-6 0"),
    Device("M8 2.5h8a2 2 0 0 1 2 2v15a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-15a2 2 0 0 1 2-2zM11 18.2h2"),
    Trash("M4 6.5h16M9.5 6.5v-2a1 1 0 0 1 1-1h3a1 1 0 0 1 1 1v2M6 6.5l.9 13a1.5 1.5 0 0 0 1.5 1.4h7.2a1.5 1.5 0 0 0 1.5-1.4l.9-13M10 11v6M14 11v6"),
    Sort("M7.5 4.5v15M7.5 4.5L4 8M7.5 4.5L11 8M16.5 19.5v-15M16.5 19.5L13 16M16.5 19.5L20 16"),
    Back("M14.5 5l-7 7 7 7"),
    Forward("M9.5 5l7 7-7 7"),
    Check("M5 12.5l4.5 4.5L19 7.5"),
    Refresh("M20 12a8 8 0 1 1-2.4-5.7M20 3.8v4.4h-4.4"),
    Sound("M4 9.5v5h3.5L12 18.5v-13L7.5 9.5zM15.5 9a4.2 4.2 0 0 1 0 6M18 6.5a7.8 7.8 0 0 1 0 11"),
    Swap("M4 8.5h14M14.5 5l3.5 3.5L14.5 12M20 16H6M9.5 12.5L6 16l3.5 3.5"),
    Cloud("M12 12m-8.5 0a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0-17 0M3.5 12h4.5M16 12h4.5M12 12m-1.6 0a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0"),
    Heart("M12 20s-7.8-4.7-7.8-10.3A4.3 4.3 0 0 1 12 7.2a4.3 4.3 0 0 1 7.8 2.5C19.8 15.3 12 20 12 20z"),
    Text("M6 2.8h8.5L19 7.3v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1v-16.500a1 1 0 0 1 1-1zM9 11h6.500M9 14.500h6.500M9 18h4"),
    Pad("M8 6.500h8a5.5 5.5 0 0 1 5.3 4l1 4.600a3 3 0 0 1-5.4 2.300L15.5 15h-7l-1.4 2.400a3 3 0 0 1-5.4-2.300l1-4.600a5.5 5.5 0 0 1 5.3-4zM8 9v4M6 11h4M15.5 10v.1M17.5 12v.1"),
    Down("M12 4v14M6 12.500l6 6 6-6"),
    Up("M12 20V6M6 11.500l6-6 6 6"),
    Pause("M9 5.500v13M15 5.500v13", stroke = 2.6f),
    Wait("M7 4h10M7 20h10M8 4c0 5 8 6 8 8s-8 3-8 8M16 4c0 5-8 6-8 8s8 3 8 8"),
    Code("M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h2.500M20 14v.1M17 17v.1M14 20h2.500M20 20v-2.500"),
    Key("M14.5 9.5m-5 0a5 5 0 1 0 10 0a5 5 0 1 0-10 0M10.800 13L4 19.800M6.500 17.300l2.500 2.500"),
    Power("M12 3.500v8M7 6.500a7.5 7.5 0 1 0 10 0"),
    Folder("M3.500 6.500a1.5 1.5 0 0 1 1.500-1.500h4.500l2 2.500h7.500a1.5 1.5 0 0 1 1.500 1.500v8.500a1.5 1.5 0 0 1-1.500 1.500h-14a1.5 1.5 0 0 1-1.500-1.500z"),
    Close("M6 6l12 12M18 6L6 18"),
    Dots,
}

/** Icons carry no meaning alone: a label or a content description always sits with them. */
@Composable
fun OortGlyph(glyph: Glyph, modifier: Modifier = Modifier, tint: Color = LocalContentColor.current) {
    Canvas(if (modifier == Modifier) Modifier.size(24.dp) else modifier) {
        val u = size.minDimension / 24f
        fun dot(x: Float, y: Float, r: Float) = drawCircle(tint, radius = r * u, center = Offset(x * u, y * u))
        fun ring(x: Float, y: Float, radius: Float, count: Int, r: Float) {
            for (i in 0 until count) {
                val a = (i.toFloat() / count * 2 * PI).toFloat()
                dot(x + radius * cos(a), y + radius * sin(a), r)
            }
        }
        val path = glyph.path
        if (path != null) {
            withTransform({ scale(u, u, Offset.Zero) }) {
                val shape = PathParser().parsePathString(path).toPath()
                if (glyph.filled) drawPath(shape, tint)
                else drawPath(shape, tint, style = Stroke(width = glyph.stroke, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            return@Canvas
        }
        when (glyph) {
            // The mark: a shell of dots and what is at its middle.
            Glyph.Home -> { dot(12f, 12f, 2.6f); ring(12f, 12f, 9f, 16, 1.25f) }
            Glyph.Library -> for (row in 0..2) for (col in 0..2) dot(5f + col * 7f, 5f + row * 7f, 1.9f)
            Glyph.Controllers -> { ring(6.8f, 12f, 4.6f, 11, 1.1f); ring(17.2f, 12f, 4.6f, 11, 1.1f) }
            Glyph.Settings -> for ((row, knob) in listOf(6, 17, 10).withIndex()) {
                val y = 5.5f + row * 6.5f
                for (i in 0..6) dot(3f + i * 3f, y, 0.9f)
                dot(knob.toFloat(), y, 2.4f)
            }
            else -> { dot(12f, 5f, 2f); dot(19f, 12f, 2f); dot(12f, 19f, 2f); dot(5f, 12f, 2f); dot(12f, 12f, 1f) }
        }
    }
}
