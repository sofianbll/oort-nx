package io.github.sofianbll.oortnx.core

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tanh

// Port of OortSynth (Sources/NXLibraryCore/Selene/OortSynth.swift, Oort NX, MIT): the interface sounds are made
// here, as 16-bit stereo PCM at 48 kHz, with no audio file. The Mac's own output for eight cases is in
// goldens.json (android/tools/make_goldens.swift) and OortSynthTest compares against it.
// One change of method: the Mac convolves the two small rooms with vDSP; here an FFT does it (the same sums).

enum class SoundEvent { Move, Select, Confirm, Back, Deny, Open, Close, Play, Resume, Success, Notification, Boot, Ambience }

/** Eight notes, in semitones above the voice's fifth, played one per step of the focus. */
enum class Figure(val notes: List<Double>) {
    Rise(listOf(0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5)),
    Major(listOf(0.0, 2.0, 4.0, 5.0, 7.0, 9.0, 11.0, 12.0)),
    Pentatonic(listOf(0.0, 2.0, 4.0, 7.0, 9.0, 12.0, 14.0, 16.0)),
    Minor(listOf(0.0, 2.0, 3.0, 5.0, 7.0, 8.0, 10.0, 12.0)),
    Arpeggio(listOf(0.0, 4.0, 7.0, 12.0, 16.0, 19.0, 16.0, 12.0)),
    Dream(listOf(0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 14.0)),
    Moonlit(listOf(0.0, 2.0, 3.0, 7.0, 8.0, 12.0, 14.0, 15.0)),
    Wave(listOf(0.0, 4.0, 7.0, 9.0, 12.0, 9.0, 7.0, 4.0)),
    Descent(listOf(12.0, 11.0, 9.0, 7.0, 5.0, 4.0, 2.0, 0.0)),
}

class OortSynth private constructor(private val voice: Voice) {
    private enum class Wave { Sine, Triangle, Square }

    private class Voice(val wave: Wave, val frequency: Double, val decay: Double, val cutoff: Double, val partials: DoubleArray)

    /** 16-bit stereo PCM (left, right, left, right...), or null when the pack leaves this event silent. */
    fun pcm(event: SoundEvent, step: Int = 0, notes: List<Double> = Figure.Rise.notes, octave: Int = 0): ShortArray? {
        val mix = Mix(if (event == SoundEvent.Boot) 2.8 else 1.6)
        when (event) {
            SoundEvent.Move -> {
                if (notes.isEmpty()) return null
                val semitones = notes[((step % notes.size) + notes.size) % notes.size]
                val shift = octave.coerceIn(OCTAVES.first, OCTAVES.last).toDouble()
                note(mix, 1.5 * 2.0.pow(semitones / 12 + shift), volume = 0.055, length = 0.45)
            }
            SoundEvent.Select -> {
                click(mix, 0.22, 1500.0)
                note(mix, 0.5, volume = 0.1, length = 0.5)
            }
            SoundEvent.Confirm -> {
                click(mix, 0.16, 2600.0)
                note(mix, 1.335, at = 0.012, volume = 0.12)
            }
            SoundEvent.Open -> {
                click(mix, 0.2, 1700.0)
                note(mix, 1.0, volume = 0.1)
                note(mix, 1.5, at = 0.06, volume = 0.09)
            }
            SoundEvent.Close, SoundEvent.Back -> note(mix, 0.75, volume = 0.1)
            SoundEvent.Deny -> {
                note(mix, 0.75, volume = 0.1)
                note(mix, 0.707, at = 0.08, volume = 0.1)
            }
            SoundEvent.Play -> {
                click(mix, 0.26, 1100.0)
                note(mix, 0.75, volume = 0.13)
                note(mix, 1.125, at = 0.07, volume = 0.13)
            }
            SoundEvent.Success -> {
                note(mix, 1.0, volume = 0.15)
                note(mix, 1.5, at = 0.09, volume = 0.15)
                note(mix, 2.0, at = 0.2, volume = 0.16, length = 2.2)
            }
            SoundEvent.Notification -> {
                note(mix, 1.0, volume = 0.14, length = 1.6)
                note(mix, 1.5, at = 0.1, volume = 0.12, length = 2.0)
            }
            SoundEvent.Resume -> {
                note(mix, 1.0, volume = 0.18, length = 1.4)
                note(mix, 1.5, at = 0.11, volume = 0.16, length = 1.8)
                note(mix, 1.25, at = 0.3, volume = 0.14, length = 2.4)
            }
            SoundEvent.Boot -> sun(mix)
            SoundEvent.Ambience -> return null
        }
        return mix.pcm()
    }

    private fun note(mix: Mix, ratio: Double, at: Double = 0.0, volume: Double, length: Double = 1.0) {
        for ((index, partial) in voice.partials.withIndex()) {
            val level = volume / (1 + index * 2.6) * (if (voice.wave == Wave.Square) 0.35 else 1.0)
            val release = voice.decay * length / (1 + index * 0.6)
            val count = ((voice.decay * length + 0.05) * RATE).toInt()
            val step = voice.frequency * ratio * partial / RATE
            val filter = LowPass(voice.cutoff, RATE)
            val samples = FloatArray(count)
            for (n in 0 until count) {
                val time = n / RATE
                val phase = (n * step).rem(1.0)
                val shape = when (voice.wave) {
                    Wave.Sine -> sin(2 * PI * phase)
                    Wave.Triangle -> 4 * abs((phase + 0.75).rem(1.0) - 0.5) - 1
                    Wave.Square -> if (phase < 0.5) 1.0 else -1.0
                }
                // 4 ms up, then an exponential fall to -80 dB.
                val envelope = if (time < 0.004) level * time / 0.004
                else level * (0.0001 / max(level, 0.0001)).pow(min(1.0, (time - 0.004) / max(0.001, release - 0.004)))
                val tail = min(1.0, (count - n) / (0.004 * RATE))
                samples[n] = (filter.run(shape) * envelope * tail).toFloat()
            }
            mix.add(samples, at)
        }
    }

    /** The Sun: three pure tones in tune with the voice, then the cloud answering on both sides. Nothing else. */
    private fun sun(mix: Mix) {
        var root = voice.frequency
        while (root > 172) root /= 2
        if (root < 118) root *= 1.5
        val length = 2.4
        val count = (length * RATE).toInt()
        fun bell(u: Double, rise: Double, fall: Double): Double =
            if (u <= 0) 0.0 else if (u < rise) 0.5 - 0.5 * cos(PI * u / rise) else exp(-(u - rise) / fall)
        class Part(val ratio: Double, val level: Double, val envelope: (Double) -> Double)
        val parts = listOf(
            Part(1.0, 1.0) { bell(it, 0.13, 0.19) + 0.26 * bell(it - 0.36, 0.15, 0.2) },
            Part(2.0, 0.17) { bell(it, 0.10, 0.14) + 0.2 * bell(it - 0.36, 0.13, 0.16) },
            Part(3.0, 0.03) { bell(it, 0.09, 0.12) },
            Part(1.0, 0.22) { bell(it - 0.1, 0.34, 0.42) },
        )
        for (part in parts) {
            var phase = 0.0
            val samples = FloatArray(count) { n ->
                val time = n / RATE
                // The pitch settles once, gently.
                phase += root * part.ratio * (1 - 0.045 * exp(-time / 0.06)) / RATE
                val close = if (time > length - 0.5) 0.5 + 0.5 * cos(PI * (time - length + 0.5) / 0.5) else 1.0
                (sin(2 * PI * phase) * part.envelope(time) * part.level * close * 0.11).toFloat()
            }
            mix.add(samples, 0.0)
        }
    }

    private fun click(mix: Mix, volume: Double, frequency: Double) {
        val count = (0.018 * RATE).toInt()
        val band = BandPass(frequency, 1.1, RATE)
        var seed = 0x6f6f7274
        val samples = FloatArray(count) { n ->
            seed = seed * 1_664_525 + 1_013_904_223 // UInt32 arithmetic: Int wraps the same way
            val noise = (seed.toLong() and 0xFFFFFFFFL).toDouble() / 4294967295.0 * 2 - 1
            (band.run(noise * (1 - n.toDouble() / count).pow(6)) * volume).toFloat()
        }
        mix.add(samples, 0.0)
    }

    private class LowPass(cutoff: Double, rate: Double) {
        private val b0: Double
        private val b1: Double
        private val b2: Double
        private val a1: Double
        private val a2: Double
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        init {
            val w = 2 * PI * min(cutoff, rate * 0.45) / rate
            val alpha = sin(w) / (2 * 0.8912)
            val a0 = 1 + alpha
            b0 = (1 - cos(w)) / 2 / a0
            b1 = (1 - cos(w)) / a0
            b2 = b0
            a1 = -2 * cos(w) / a0
            a2 = (1 - alpha) / a0
        }

        fun run(x: Double): Double {
            val y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private class BandPass(center: Double, q: Double, rate: Double) {
        private val b0: Double
        private val a1: Double
        private val a2: Double
        private var x1 = 0.0
        private var x2 = 0.0
        private var y1 = 0.0
        private var y2 = 0.0

        init {
            val w = 2 * PI * center / rate
            val alpha = sin(w) / (2 * q)
            val a0 = 1 + alpha
            b0 = alpha / a0
            a1 = -2 * cos(w) / a0
            a2 = (1 - alpha) / a0
        }

        fun run(x: Double): Double {
            val y = b0 * x - b0 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x; y2 = y1; y1 = y
            return y
        }
    }

    private class Mix(seconds: Double) {
        private val dry = FloatArray((seconds * RATE).toInt())

        fun add(samples: FloatArray, start: Double) {
            val offset = (start * RATE).toInt()
            for (index in samples.indices) if (offset + index < dry.size) dry[offset + index] += samples[index]
        }

        /** Two decorrelated short rooms, then a soft ceiling: nothing can clip. */
        fun pcm(): ShortArray {
            val length = dry.size
            val sides = intArrayOf(5, 11).map { seed ->
                val wet = convolve(dry, Rooms.spectrum(seed))
                FloatArray(length) { n -> (tanh(0.55f * (dry[n] + 0.12f * wet[n]) * 1.4f) / 1.4f) }
            }
            // Silence at the end is not worth keeping.
            val last = (sides.maxOf { side -> side.indexOfLast { abs(it) > 0.00003f } }.coerceAtLeast(0)) + 480
            val frames = min(length, last)
            val out = ShortArray(frames * 2)
            for (n in 0 until frames) {
                val fade = min(1f, (frames - n) / 240f)
                for ((i, side) in sides.withIndex()) {
                    out[n * 2 + i] = (max(-1f, min(1f, side[n] * fade)) * 32_767f).toInt().toShort()
                }
            }
            return out
        }
    }

    /** The small rooms of the Mac's reverb, as unit-energy noise bursts, kept in the frequency domain. */
    internal object Rooms {
        private val cache = HashMap<Int, Spectrum>()

        @Synchronized
        fun spectrum(seed: Int): Spectrum = cache.getOrPut(seed) {
            var s = seed
            val count = (RATE * 0.5).toInt()
            val room = FloatArray(count) { n ->
                s = s * 1_664_525 + 1_013_904_223
                ((s.toLong() and 0xFFFFFFFFL).toFloat() / 4294967295f * 2 - 1) * (1 - n.toFloat() / count).pow(3.2f)
            }
            // The level WebAudio gives a convolution: unit energy.
            var energy = 0f
            for (v in room) energy += v * v
            val scale = 1f / max(0.0001f, sqrt(energy))
            val re = DoubleArray(FFT_SIZE)
            for (n in 0 until count) re[n] = (room[n] * scale).toDouble()
            val im = DoubleArray(FFT_SIZE)
            fft(re, im, inverse = false)
            Spectrum(re, im)
        }
    }

    internal class Spectrum(val re: DoubleArray, val im: DoubleArray)

    companion object {
        const val RATE = 48_000.0
        val OCTAVES = -2..2
        val RANGE = 0.0..24.0

        // dry (at most 2.8 s) + room (0.5 s) fit in one transform
        internal const val FFT_SIZE = 1 shl 18

        private val VOICES = mapOf(
            "oort" to Voice(Wave.Sine, 523.0, 0.16, 5200.0, doubleArrayOf(1.0, 2.01)),
            "pollen" to Voice(Wave.Sine, 659.0, 0.28, 6500.0, doubleArrayOf(1.0, 3.9)),
            "umbra" to Voice(Wave.Triangle, 262.0, 0.24, 1500.0, doubleArrayOf(1.0, 1.5)),
            "impulsion" to Voice(Wave.Square, 392.0, 0.07, 2600.0, doubleArrayOf(1.0)),
        )

        val packs: List<String> = VOICES.keys.toList()

        fun of(pack: String): OortSynth? = VOICES[pack]?.let { OortSynth(it) }

        /** Eight notes inside the range, or the figure's own when the stored ones are not usable. */
        fun notes(figure: Figure, custom: List<Double>? = null): List<Double> =
            if (custom != null && custom.size == 8 && custom.all { it.isFinite() }) custom.map { it.coerceIn(RANGE.start, RANGE.endInclusive) }
            else figure.notes

        internal fun convolve(dry: FloatArray, room: Spectrum): FloatArray {
            val re = DoubleArray(FFT_SIZE)
            val im = DoubleArray(FFT_SIZE)
            for (n in dry.indices) re[n] = dry[n].toDouble()
            fft(re, im, inverse = false)
            for (k in 0 until FFT_SIZE) {
                val r = re[k] * room.re[k] - im[k] * room.im[k]
                im[k] = re[k] * room.im[k] + im[k] * room.re[k]
                re[k] = r
            }
            fft(re, im, inverse = true)
            return FloatArray(dry.size) { re[it].toFloat() }
        }

        /** In-place iterative radix-2 transform; the inverse is scaled by 1/n. */
        internal fun fft(re: DoubleArray, im: DoubleArray, inverse: Boolean) {
            val n = re.size
            var j = 0
            for (i in 1 until n) {
                var bit = n shr 1
                while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
                j = j xor bit
                if (i < j) {
                    val tr = re[i]; re[i] = re[j]; re[j] = tr
                    val ti = im[i]; im[i] = im[j]; im[j] = ti
                }
            }
            var len = 2
            while (len <= n) {
                val angle = 2 * PI / len * (if (inverse) 1 else -1)
                val wr = cos(angle)
                val wi = sin(angle)
                var start = 0
                while (start < n) {
                    var cr = 1.0
                    var ci = 0.0
                    for (k in 0 until len / 2) {
                        val a = start + k
                        val b = a + len / 2
                        val xr = re[b] * cr - im[b] * ci
                        val xi = re[b] * ci + im[b] * cr
                        re[b] = re[a] - xr; im[b] = im[a] - xi
                        re[a] += xr; im[a] += xi
                        val next = cr * wr - ci * wi
                        ci = cr * wi + ci * wr
                        cr = next
                    }
                    start += len
                }
                len = len shl 1
            }
            if (inverse) for (i in 0 until n) { re[i] /= n; im[i] /= n }
        }
    }
}
