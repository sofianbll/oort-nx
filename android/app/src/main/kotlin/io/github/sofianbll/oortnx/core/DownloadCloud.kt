package io.github.sofianbll.oortnx.core

import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** The Mac's download cloud (`Sources/OortCore/DownloadCloudMotion.swift`), the same numbers: a level that never runs ahead of the bytes. */
object DownloadCloud {
    class Surface(val level: Double?, val energy: Double, val activity: Double, val phase: Double) {
        fun y(x: Double, w: Double, h: Double): Double {
            val y = h * (1 - (level ?: 0.5))
            val u = x / w - 0.5
            val scale = min(w, h) / 170
            val room = ease(min(y, h - y) / (16 * scale))
            val a = 2 * PI * (u * 1.10 - phase / 5.6) + 0.3
            val b = 2 * PI * (u * 1.93 + phase / 8.7) - 0.5
            val ripple = 0.77 * (sin(a) - sin(a - 2 * PI * u * 1.10) * sin(PI * 1.10) / (PI * 1.10)) +
                0.23 * (sin(b) - sin(b - 2 * PI * u * 1.93) * sin(PI * 1.93) / (PI * 1.93))
            return y + scale * room * 5.4 * energy * ripple
        }
    }

    class Band(val level: Double, val opacity: Double)
    class Sample(val surface: Surface, val opacity: Double, val bands: List<Band>)
    class Dot(val x: Double, val y: Double, val radius: Double, val opacity: Double, val accent: Boolean)

    /** Moving (`drift`) or at rest (`settle`), at a level from 0 to 1. */
    class Track(level: Double, moving: Boolean, private val appeared: Double, private val reduced: Boolean = false) {
        private val duration = if (reduced) 0.52 else 3.2
        private var base = level.coerceIn(0.0, 1.0)
        private val steps = ArrayDeque<Pair<Double, Double>>()
        private val target get() = steps.lastOrNull()?.second ?: base
        private var waveBase = 0.0
        private var waveTarget = 0.0
        private val wave = ArrayDeque<Pair<Double, Double>>()
        private var sleep: Double? = null
        private var was = moving

        init { if (moving && !reduced) { set(1.0, appeared); sleep = appeared + SILENCE } }

        fun receive(level: Double, moving: Boolean, at: Double, advanced: Boolean = true) {
            val next = level.coerceIn(0.0, 1.0)
            val changed = next != target || moving != was
            if (next > target) {
                val time = max(at, appeared)
                while (steps.isNotEmpty() && time - steps.first().first >= duration) base = steps.removeFirst().second
                if (steps.lastOrNull()?.first == time) steps.removeLast()
                steps.add(time to next)
            }
            if (!reduced) {
                sleep?.let { if (it <= at) { set(0.0, it); sleep = null } }
                if (moving) { if (advanced || changed) { set(1.0, at); sleep = at + SILENCE } }
                else if (changed) { set(0.0, at); sleep = null }
            }
            was = moving
        }

        private fun set(to: Double, at: Double) {
            if (to == waveTarget) return
            while (wave.isNotEmpty() && at - wave.first().first >= WAVE) waveBase += wave.removeFirst().second
            wave.add(at to to - waveTarget)
            waveTarget = to
        }

        val end: Double get() = maxOf(appeared + 0.38, (steps.lastOrNull()?.first ?: Double.NEGATIVE_INFINITY) + duration,
            (wave.lastOrNull()?.first ?: Double.NEGATIVE_INFINITY) + WAVE, (sleep ?: Double.NEGATIVE_INFINITY) + WAVE)

        fun sample(at: Double): Sample {
            var previous = base
            var level = base
            for ((time, next) in steps) {
                val t = max(0.0, at - time)
                val u = 2.05 * t
                val response = if (reduced) ease(t / duration) else if (t >= duration) 1.0
                    else 1 - exp(-u) * (1 + u + u * u / 2) * (1 - ease((t - 1.8) / (duration - 1.8)))
                level += (next - previous) * response
                previous = next
            }
            var energy = wave.fold(waveBase) { sum, (time, by) -> sum + by * ease((at - time) / WAVE) }
            sleep?.let { energy -= ease((at - it) / WAVE) }
            energy = energy.coerceIn(0.0, 1.0)
            return Sample(Surface(min(max(0.0, level), previous), energy, energy, if (reduced) 0.0 else at), ease((at - appeared) / 0.38), if (reduced) bands(at) else emptyList())
        }

        private fun bands(at: Double): List<Band> {
            val result = ArrayList<Band>()
            if (base > 0) result.add(Band(base, 1.0))
            for ((time, level) in steps) if (level > 0) {
                val alpha = ease((at - time) / duration)
                if (result.lastOrNull()?.opacity == alpha) result.removeAt(result.lastIndex)
                result.add(Band(level, alpha))
            }
            return result
        }
    }

    fun dots(surface: Surface, seed: Long, w: Double, h: Double): List<Dot> {
        val scale = min(w, h) / 170
        val random = SplitMix(seed)
        val width = if (surface.level == null) 0.74 else 0.88
        val columns = 16
        val clock = surface.phase / 5.6
        val dots = ArrayList<Dot>(32)
        for (row in 0..1) for (column in 0 until columns) {
            val phase = 2 * PI * random.unit()
            val spacing = w * width / columns
            val sway = 2 * PI * clock + phase
            val jitter = (random.unit() - 0.5) * 0.83 + 0.23 * sin(sway) * surface.activity
            val cycles = clock * 1.7 + phase / (2 * PI)
            val bubble = cycles - floor(cycles)
            val x = w * (1 - width) / 2 + (column + 0.45 + jitter) * spacing
            val crest = surface.y(x, w, h)
            val depth = if (row == 0) 3.0 + 2.0 * random.unit() else 4 + 18 * bubble
            val y = max(2.5 * scale, crest - depth * scale)
            val radius = (if (row == 0) 0.98 + 0.51 * random.unit() else 0.62) * scale
            val shimmer = if (row == 0) 0.967 + 0.033 * sin(sway) else 0.64 * sin(PI * bubble)
            val visible = row == 0 || column % 3 == 0
            val reach = if (row == 0) 0.2 + 0.8 * ease(crest / (7 * scale)) else ease(crest / (17 * scale))
            dots.add(Dot(x, y, radius, if (visible) reach * surface.activity * shimmer else 0.0, row == 1 || column % 3 == 0))
        }
        return dots
    }

    /** A dot's light reaches this many radii (the Mac's `DownloadCloudSprites.rect`). */
    const val SPRITE_REACH = 2.8

    /** The front's own line (the Mac's `DownloadCloudFront.lineOpacity`). */
    fun lineOpacity(surface: Surface): Double {
        val level = surface.level ?: return 0.0
        val edge = min(1.0, min(level, 1 - level) * 40)
        return edge * edge * (3 - 2 * edge) * 0.71 * surface.activity
    }

    private const val SILENCE = 1.4
    private const val WAVE = 2.0

    fun ease(x: Double): Double {
        val p = x.coerceIn(0.0, 1.0)
        return p * p * p * (10 + p * (-15 + 6 * p))
    }

    private class SplitMix(private var state: Long) {
        private fun next(): Long {
            state += -0x61c8864680b583ebL
            var z = state
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }
        fun unit(): Double = (next() ushr 11).toDouble() / (1L shl 53).toDouble()
    }
}
