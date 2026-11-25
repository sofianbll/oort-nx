package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals

/** Against what the Mac's own Swift printed (tools/README in download-cloud.txt's commit): levels, waves, dots and still bands. */
class DownloadCloudTest {
    @Test fun `the same numbers as the Mac`() {
        val track = DownloadCloud.Track(0.0, true, 0.0)
        track.receive(0.2, true, 0.5)
        track.receive(0.6, true, 1.4)
        track.receive(0.6, false, 4.0, advanced = false)
        val still = DownloadCloud.Track(0.0, true, 0.0, reduced = true)
        still.receive(0.5, true, 1.0)
        var seen = 0
        for (line in javaClass.getResource("/download-cloud.txt")!!.readText().trim().lines()) {
            val words = line.split(" ")
            fun same(expected: String, got: Double) = assertEquals(expected.toDouble(), got, 1e-6, line)
            val sample = (if (words[0] == "R") still else track).sample(words[1].toDouble())
            when (words[0]) {
                "T" -> {
                    same(words[2], sample.surface.level!!)
                    same(words[3], sample.surface.energy)
                    same(words[4], sample.surface.activity)
                    same(words[5], sample.opacity)
                    same(words[6], sample.surface.y(30.0, 170.0, 170.0))
                    same(words[7], sample.surface.y(140.0, 170.0, 170.0))
                }
                "D" -> {
                    val dot = DownloadCloud.dots(sample.surface, 0x0100000000AA1000, 170.0, 170.0)[words[2].toInt()]
                    same(words[3], dot.x)
                    same(words[4], dot.y)
                    same(words[5], dot.radius)
                    same(words[6], dot.opacity)
                }
                "R" -> {
                    same(words[2], sample.surface.level!!)
                    assertEquals(words.drop(3).first().split(",").map { it.split(":")[0].toDouble() }, sample.bands.map { it.level }, line)
                    sample.bands.zip(words[3].split(",")).forEach { (band, text) -> same(text.split(":")[1], band.opacity) }
                }
            }
            seen++
        }
        assertEquals(49, seen)
    }
}
