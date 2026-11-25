package io.github.sofianbll.oortnx.core

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// Port of OortCloudPoint.field() (Sources/NXLibraryCore/Selene/MoonlightAppearance.swift, Oort NX, MIT).
// A line-by-line copy of android/tools/verify_cloud.py, which was checked against the Swift output
// (goldens.json): same float32 steps, same order of operations.

enum class CloudKind { Shell, Rim, Disc }

/** One dot of the cloud: unit radius, y down, the cut facing the viewer. */
class CloudPoint(
    val x: Float, val y: Float, val z: Float,
    val kind: CloudKind,
    val nx: Float, val ny: Float, val nz: Float,
)

object OortCloud {
    private const val TWO_PI = (2.0 * PI).toFloat()

    /** The site's cloud, made once. 12,710 points. */
    fun field(): List<CloudPoint> {
        var seed = 5L
        fun random(): Float {
            seed = seed * 16807L % 2_147_483_647L
            return seed.toFloat() / 2_147_483_647f
        }

        val points = ArrayList<CloudPoint>(12_800)
        fun add(x: Float, y: Float, z: Float, kind: CloudKind, nx: Float, ny: Float, nz: Float) {
            points.add(CloudPoint(x, y, z, kind, nx, ny, nz))
        }

        val pi = PI.toFloat()
        val shell = 9_800
        val golden = pi * (3f - sqrt(5f))
        for (i in 0 until shell) {
            val y = 1f - 2f * (i.toFloat() + 0.5f) / shell.toFloat()
            val r = sqrt(1f - y * y)
            val a = (i.toFloat() * golden).rem(TWO_PI)
            val x = cos(a) * r
            val z = sin(a) * r
            if (z > 0.1f) continue
            val k = 0.9f + 0.1f * random()
            add(x * k, y * k, z * k, CloudKind.Shell, x, y, z)
        }
        for (j in 0 until 9) {
            val r = 1f - j.toFloat() * 0.0165f
            val count = 330 - j * 16
            for (i in 0 until count) {
                val a = i.toFloat() / count.toFloat() * 2f * pi + j.toFloat() * 0.02f
                val side = cos(a)
                if (side < 0.15f && j.toFloat() > 3f + side * 3f + 3f) continue
                add(cos(a) * r, sin(a) * r, 0.1f - j.toFloat() * 0.003f, CloudKind.Rim, 0f, 0f, 1f)
            }
        }
        for (k in 0 until 30) {
            val t = 0.16f + k.toFloat() * 0.0262f
            val count = (t * 150f + 0.5f).toInt()
            val thickness = 0.004f + 0.085f * t.pow(2.8f)
            val layers = maxOf(1, (thickness / 0.016f + 0.5f).toInt())
            for (j in 0 until layers) {
                val h = if (layers == 1) 0f else (j.toFloat() / (layers - 1).toFloat() - 0.5f) * 2f * thickness
                for (i in 0 until count) {
                    val a = (i.toFloat() + ((k + j) % 2).toFloat() * 0.5f) / count.toFloat() * 2f * pi
                    add(cos(a) * t, h, sin(a) * t, CloudKind.Disc, 0f, if (h < 0f) -1f else 1f, 0f)
                }
            }
        }
        return points
    }
}
