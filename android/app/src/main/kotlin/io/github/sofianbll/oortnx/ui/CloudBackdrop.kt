package io.github.sofianbll.oortnx.ui

import android.graphics.Paint
import android.graphics.RuntimeShader
import android.os.Build
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import io.github.sofianbll.oortnx.core.CloudKind
import io.github.sofianbll.oortnx.core.CloudLayout
import io.github.sofianbll.oortnx.core.CloudPoint
import io.github.sofianbll.oortnx.core.OortCloud
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The Oort cloud in cross-section, after the Mac's cloud surface (MoonlightShaders.swift `cloud_dot_*`): a shell of
 * dots, its disc turning slowly, and the Sun, the only gold. Points are drawn by Canvas (any Android from 10);
 * the Sun's glow is an AGSL shader from Android 13, with a radial gradient before.
 *
 * It moves at 30 images a second: the motion is a slow turn, and a launcher is often played for hours on a battery.
 * With [still] it is one image.
 */
@Composable
fun CloudBackdrop(still: Boolean, strength: Float, modifier: Modifier = Modifier) {
    val renderer = remember { CloudRenderer(OortCloud.field()) }
    val sun = remember { if (Build.VERSION.SDK_INT >= 33) SunShader() else null }
    var time by remember { mutableFloatStateOf(STILL_TIME) }

    LaunchedEffect(still) {
        if (still) return@LaunchedEffect
        var last = 0L
        while (true) {
            androidx.compose.runtime.withFrameNanos { now ->
                // The clock stops with the window, so nothing jumps on return.
                if (last == 0L) last = now
                if (now - last >= FRAME_NANOS) { time += min((now - last) / 1e9f, 0.1f); last = now }
            }
        }
    }

    Box(modifier.fillMaxSize().background(OortTokens.Palette.Scrim)) {
        Canvas(Modifier.fillMaxSize()) {
            drawRect(
                Brush.radialGradient(
                    listOf(OortTokens.Palette.GradientStart, OortTokens.Palette.GradientEnd),
                    center = Offset(size.width, 0f),
                    radius = max(1f, max(size.width, size.height)),
                ),
            )
        }
        // Its own layer: a frame redraws the cloud and nothing above it.
        Canvas(Modifier.fillMaxSize().graphicsLayer { alpha = strength }) {
            if (size.minDimension < 1f) return@Canvas
            val t = time
            val layout = CloudLayout.of(size.width, size.height)
            drawIntoCanvas { renderer.draw(it.nativeCanvas, layout, t, OortTokens.Palette.Light) }
            // On the list screens rows and names pass over the cloud's centre: the Sun stays on the home screen.
            if (strength > 0.8f) drawSun(layout, t, sun)
        }
    }
}

private const val STILL_TIME = 8f
private const val FRAME_NANOS = 33_000_000L

private fun DrawScope.drawSun(layout: CloudLayout, t: Float, shader: SunShader?) {
    val breath = 0.5f + 0.5f * sin(t * 0.35f)
    if (shader != null) {
        drawRect(shader.brush(layout, t, breath))
        return
    }
    // Before Android 13: the disc and a soft halo, without the AGSL dither.
    val unit = layout.unit
    val sun = CHARTER_SUN
    val centre = Offset(layout.centreX, layout.centreY)
    drawCircle(
        Brush.radialGradient(
            listOf(sun.copy(alpha = 0.05f * (0.8f + 0.2f * breath) * 4f), Color.Transparent),
            center = centre, radius = unit * 0.2f,
        ),
        radius = unit * 0.2f, center = centre,
    )
    drawCircle(sun.copy(alpha = 0.82f), radius = CLOUD_SUN * unit, center = centre)
}

/** The charter's one gold, #F4CE8E: the cloud's Sun. See scripts/make_dmg_background.swift and the Mac shader. */
val CHARTER_SUN = Color(0xFFF4CE8E)
private const val CLOUD_SUN = 0.018f

@androidx.annotation.RequiresApi(33)
private class SunShader {
    private val shader = RuntimeShader(AGSL)
    private val shaderBrush = ShaderBrush(shader)

    fun brush(layout: CloudLayout, t: Float, breath: Float): ShaderBrush {
        shader.setFloatUniform("size", layout.width, layout.height)
        shader.setFloatUniform("centre", layout.centreX, layout.centreY)
        shader.setFloatUniform("unit", layout.unit)
        shader.setFloatUniform("time", t)
        shader.setFloatUniform("breath", breath)
        shader.setFloatUniform("sun", 0.957f, 0.808f, 0.557f)
        shader.setFloatUniform("accent", 0.596f, 0.651f, 0.741f)
        return shaderBrush
    }

    private companion object {
        // The Mac's sun in moon_light_fragment: disc, a faint core glow and a wide halo; dithered so the dark never bands.
        const val AGSL = """
uniform float2 size;
uniform float2 centre;
uniform float unit;
uniform float time;
uniform float breath;
uniform float3 sun;
uniform float3 accent;

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

half4 main(float2 fragCoord) {
    float d = length(fragCoord - centre) / unit;
    float disc = 1.0 - smoothstep(0.018, 0.018 + 1.2 / unit, d);
    float3 c = sun * (disc * 0.82 + exp(-d * d * 90.0) * 0.05 * (0.8 + 0.2 * breath))
             + accent * exp(-d * d * 3.2) * 0.035;
    c += (hash21(fragCoord + fract(time)) - 0.5) / 255.0;
    c = clamp(c, 0.0, 1.0);
    return half4(half3(c), half(max(c.r, max(c.g, c.b))));
}
"""
    }
}

/**
 * The cloud's dots, moved each frame as the Mac's vertex shader does and drawn in batches: dots of one size class
 * and one brightness level go to Canvas.drawPoints together, so a frame is a few dozen draw calls, not 12,000.
 */
class CloudRenderer(points: List<CloudPoint>) {
    private val n = points.size
    private val place = FloatArray(n * 3)
    private val normal = FloatArray(n * 3)
    private val kind = IntArray(n)

    private val buckets = Array(LEVELS * SIZES) { FloatArray(256) }
    private val counts = IntArray(LEVELS * SIZES)
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; style = Paint.Style.STROKE }

    init {
        for ((i, p) in points.withIndex()) {
            place[i * 3] = p.x; place[i * 3 + 1] = p.y; place[i * 3 + 2] = p.z
            normal[i * 3] = p.nx; normal[i * 3 + 1] = p.ny; normal[i * 3 + 2] = p.nz
            kind[i] = p.kind.ordinal
        }
    }

    fun draw(canvas: android.graphics.Canvas, layout: CloudLayout, t: Float, colour: Color) {
        counts.fill(0)
        val h = layout.unit
        // The shell sways and the disc turns (cloud_dot_vertex).
        val ya = -0.36f + sin(t * 0.16f) * 0.10f
        val xa = 0.30f + sin(t * 0.12f) * 0.05f
        val ca = cos(ya); val sa = sin(ya); val cb = cos(xa); val sb = sin(xa)
        val spin = t * 0.045f
        val cs = cos(spin); val ss = sin(spin)
        val tide = (t / 19f).rem(1f) * 1.9f - 0.25f
        val sunPx = CLOUD_SUN * h

        for (i in 0 until n) {
            var px = place[i * 3]; val py = place[i * 3 + 1]; var pz = place[i * 3 + 2]
            val k = kind[i]
            val length = sqrt(px * px + py * py + pz * pz)
            if (k == CloudKind.Disc.ordinal) { val nx = px * cs - pz * ss; pz = px * ss + pz * cs; px = nx }
            val rx = px * ca + pz * sa
            val rz0 = -px * sa + pz * ca
            val ry = py * cb - rz0 * sb
            val rz = py * sb + rz0 * cb
            val perspective = 3.4f / (3.4f - rz)
            val x = layout.centreX + rx * 0.5f * h * perspective
            val y = layout.centreY + ry * 0.5f * h * perspective

            if (x < -4f || y < -4f || x > layout.width + 4f || y > layout.height + 4f) continue
            var lum: Float
            val rad: Float
            if (k == CloudKind.Shell.ordinal) {
                val nx = normal[i * 3]; val ny0 = normal[i * 3 + 1]; val nz = normal[i * 3 + 2]
                val mx = nx * ca + nz * sa
                val mz0 = -nx * sa + nz * ca
                val my = ny0 * cb - mz0 * sb
                val mz = ny0 * sb + mz0 * cb
                val lit = max(0f, -(mx * -0.62f + my * -0.5f + mz * 0.6f))
                lum = lit * 0.62f + 0.07f + 0.2f * max(0f, 1f - length * 0.2f - kotlin.math.abs(py))
                rad = 0.0034f + 0.0046f * lum
            } else if (k == CloudKind.Rim.ordinal) {
                val lit = 0.5f + 0.5f * (px * 0.86f - py * 0.25f)
                lum = 0.35f + 0.65f * lit
                rad = 0.0032f + 0.0058f * lit
            } else {
                val d = sqrt(px * px + pz * pz)
                lum = 0.16f + 0.5f * max(0f, 1f - d * 0.95f) + 0.42f * max(0f, rz * 0.9f + 0.12f)
                rad = 0.0022f + 0.0026f * (1f - d * 0.4f) + 0.0016f * max(0f, rz)
            }
            // A slow tide of light leaves the Sun now and then.
            val wave = (length - tide) * 7f
            lum += exp(-wave * wave) * 0.16f
            // Quiet where titles and rows sit; nothing shines through the Sun.
            var calm = layout.calm(x, y)
            val dx = x - layout.centreX
            val dy = y - layout.centreY
            val fromSun = sqrt(dx * dx + dy * dy)
            calm *= CloudLayout.smoothstep(sunPx * 1.05f, sunPx * 1.6f, fromSun)
            val alpha = min(lum, 1f) * calm * 0.60f
            if (alpha < 0.02f) continue
            val radius = max(rad * 0.64f * 0.5f * h * perspective, 0.55f)
            val level = min(LEVELS - 1, (alpha / 0.6f * LEVELS).toInt())
            val size = (ln(radius / SMALLEST) / STEP + 0.5f).toInt().coerceIn(0, SIZES - 1)
            val b = level * SIZES + size
            val c = counts[b]
            if (buckets[b].size < c * 2 + 2) buckets[b] = buckets[b].copyOf(buckets[b].size * 2)
            buckets[b][c * 2] = x
            buckets[b][c * 2 + 1] = y
            counts[b] = c + 1
        }

        val r = (colour.red * 255).toInt(); val g = (colour.green * 255).toInt(); val bl = (colour.blue * 255).toInt()
        for (level in 0 until LEVELS) for (size in 0 until SIZES) {
            val b = level * SIZES + size
            if (counts[b] == 0) continue
            paint.color = android.graphics.Color.argb(((level + 0.5f) / LEVELS * 0.6f * 255f).toInt().coerceIn(8, 255), r, g, bl)
            paint.strokeWidth = 2f * SMALLEST * exp(size * STEP)
            canvas.drawPoints(buckets[b], 0, counts[b] * 2, paint)
        }
    }

    private companion object {
        const val LEVELS = 8
        /** Radii in px, each a third larger than the one before: 0.6 to about 7, for a phone as for a tablet. */
        const val SIZES = 9
        const val SMALLEST = 0.6f
        const val STEP = 0.3f
    }
}
