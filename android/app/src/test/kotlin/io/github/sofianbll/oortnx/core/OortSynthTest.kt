package io.github.sofianbll.oortnx.core

import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class OortSynthTest {
    private fun left(pcm: ShortArray) = IntArray(pcm.size / 2) { pcm[it * 2].toInt() }

    @Test fun matchesTheMacsOutputForEightCases() {
        for (g in Goldens.SOUNDS) {
            val synth = assertNotNull(OortSynth.of(g.pack), g.pack)
            val event = SoundEvent.valueOf(g.event.replaceFirstChar { it.uppercase() })
            val samples = left(assertNotNull(synth.pcm(event, g.step), "${g.pack}/${g.event}"))
            val label = "${g.pack}/${g.event}/${g.step}"
            // The trailing silence is cut where the signal falls under 3e-5: a few hundred frames of slack.
            assertTrue(abs(samples.size - g.frames) <= g.frames / 50 + 480, "$label frames ${samples.size} vs ${g.frames}")
            val rms = sqrt(samples.sumOf { it.toDouble() * it } / samples.size)
            assertTrue(abs(rms - g.rms) <= g.rms * 0.03 + 1, "$label rms $rms vs ${g.rms}")
            for ((index, want) in g.probes) {
                if (index >= samples.size) continue
                assertTrue(abs(samples[index] - want) <= 40 + abs(want) / 50, "$label sample $index: ${samples[index]} vs $want")
            }
        }
    }

    @Test fun theAmbienceIsSilentAndEveryOtherEventSounds() {
        val synth = assertNotNull(OortSynth.of("oort"))
        assertNull(synth.pcm(SoundEvent.Ambience))
        for (event in SoundEvent.entries - SoundEvent.Ambience) {
            val pcm = assertNotNull(synth.pcm(event), event.name)
            assertTrue(pcm.size >= 1000 && pcm.size % 2 == 0, event.name)
            assertTrue(pcm.any { abs(it.toInt()) > 100 }, "$event is not silent")
        }
    }

    @Test fun anUnknownPackIsRefused() = assertNull(OortSynth.of("nowhere"))

    @Test fun theMovesClimbWithTheStep() {
        val synth = assertNotNull(OortSynth.of("oort"))
        val a = assertNotNull(synth.pcm(SoundEvent.Move, step = 0))
        val b = assertNotNull(synth.pcm(SoundEvent.Move, step = 7))
        assertTrue(!a.contentEquals(b))
        // Eight steps wrap round.
        assertTrue(a.contentEquals(assertNotNull(synth.pcm(SoundEvent.Move, step = 8))))
    }

    @Test fun neverClips() {
        val synth = assertNotNull(OortSynth.of("umbra"))
        for (event in listOf(SoundEvent.Success, SoundEvent.Resume, SoundEvent.Boot)) {
            val pcm = assertNotNull(synth.pcm(event))
            assertTrue(pcm.all { abs(it.toInt()) < 32_767 }, event.name)
        }
    }

    @Test fun theFftIsItsOwnInverse() {
        val re = DoubleArray(1024) { sqrt(it.toDouble()) % 3 - 1 }
        val im = DoubleArray(1024)
        val keep = re.copyOf()
        OortSynth.fft(re, im, inverse = false)
        OortSynth.fft(re, im, inverse = true)
        for (i in keep.indices) assertEquals(keep[i], re[i], 1e-9)
    }

    @Test fun octaveShiftsThePitchAnOctave() {
        val synth = assertNotNull(OortSynth.of("oort"))
        val low = assertNotNull(synth.pcm(SoundEvent.Move, 0, Figure.Rise.notes, -1))
        val high = assertNotNull(synth.pcm(SoundEvent.Move, 0, Figure.Rise.notes, 1))
        fun crossings(p: ShortArray) = (2 until p.size step 2).count { (p[it - 2] < 0) != (p[it] < 0) }
        assertTrue(crossings(high) > crossings(low) * 2.4, "two octaves apart: ${crossings(low)} vs ${crossings(high)}")
    }
}
