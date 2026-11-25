package io.github.sofianbll.oortnx.core

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class OortCloudTest {
    private val field = OortCloud.field()

    @Test fun hasTheMacsPointCount() = assertEquals(Goldens.CLOUD_COUNT, field.size)

    @Test fun hasTheMacsPointsOfEachKind() {
        for (kind in CloudKind.entries) {
            val golden = Goldens.CLOUD_KINDS[kind.ordinal]
            val part = field.filter { it.kind == kind }
            assertEquals(golden[0].toInt(), part.size, "count of $kind")
            // Thousands of points, each angle within a float32 ulp of Swift's: the sums agree to about 1.
            assertTrue(abs(part.sumOf { it.x.toDouble() } - golden[1]) < 1.0, "sum x of $kind")
            assertTrue(abs(part.sumOf { it.y.toDouble() } - golden[2]) < 1.0, "sum y of $kind")
            assertTrue(abs(part.sumOf { it.z.toDouble() } - golden[3]) < 1.0, "sum z of $kind")
        }
    }

    @Test fun samplePointsMatchTheMacsWithinAFloatUlpOfTheAngle() {
        for (s in Goldens.CLOUD_SAMPLES) {
            val p = field[s[0].toInt()]
            val got = doubleArrayOf(p.x.toDouble(), p.y.toDouble(), p.z.toDouble(), p.kind.ordinal.toDouble(), p.nx.toDouble(), p.ny.toDouble(), p.nz.toDouble())
            for (i in got.indices) assertTrue(abs(got[i] - s[i + 1]) < 2e-3, "point ${s[0].toInt()} component $i: ${got[i]} vs ${s[i + 1]}")
        }
    }

    @Test fun isTheSameEveryTime() {
        val again = OortCloud.field()
        assertEquals(field.size, again.size)
        assertTrue(field.indices.all { field[it].x == again[it].x && field[it].z == again[it].z })
    }

    @Test fun shellPointsFaceAwayFromTheViewer() {
        // The cut: the shell keeps only the points with z <= 0.1 (the half seen from inside).
        assertTrue(field.filter { it.kind == CloudKind.Shell }.all { it.nz <= 0.1f })
    }
}
