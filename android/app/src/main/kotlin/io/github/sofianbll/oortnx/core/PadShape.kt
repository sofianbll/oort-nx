package io.github.sofianbll.oortnx.core

import kotlin.math.hypot

/**
 * Port of OortCore's OortPadShape (Oort NX, MIT): the controller drawn in dots, as places only. The middle of the pad
 * is the origin, half its width is 1, y goes down.
 */
object PadShape {
    data class Point(val x: Double, val y: Double)

    enum class Place { LeftStick, RightStick, Up, Down, Left, Right, Top, West, East, Bottom, View, Menu, Home }

    class Part(val place: Place, val x: Double, val y: Double, val radius: Double)

    /** One dot, the part it belongs to, and how far from that part's middle it is (0 to 1). */
    class Cell(val x: Double, val y: Double, val part: Place?, val edge: Double)

    val parts = listOf(
        Part(Place.LeftStick, -0.43, -0.23, 0.135), Part(Place.RightStick, 0.24, 0.05, 0.125),
        Part(Place.Up, -0.145, 0.025, 0.045), Part(Place.Down, -0.145, 0.175, 0.045),
        Part(Place.Left, -0.22, 0.1, 0.045), Part(Place.Right, -0.07, 0.1, 0.045),
        Part(Place.Top, 0.467, -0.36, 0.062), Part(Place.West, 0.343, -0.24, 0.062),
        Part(Place.East, 0.59, -0.24, 0.062), Part(Place.Bottom, 0.467, -0.115, 0.062),
        Part(Place.View, -0.16, -0.3, 0.038), Part(Place.Menu, 0.16, -0.3, 0.038),
        Part(Place.Home, 0.0, -0.2, 0.045),
    )

    val cells: List<Cell> by lazy {
        val line = outline()
        val step = 8.2
        val out = ArrayList<Cell>(1_100)
        var row = 0
        while (row * step * 0.866 < 300.0) {
            val y = row * step * 0.866
            val start = (row % 2) * step / 2
            var column = 0
            while (start + column * step < 420.0) {
                val x = start + column * step
                if (contains(x, y, line)) {
                    val px = (x - 210) / 210
                    val py = (y - 150) / 210
                    val near = parts.map { it to hypot(px - it.x, py - it.y) }.filter { it.second < it.first.radius }.minByOrNull { it.second }
                    out.add(Cell(px, py, near?.first?.place, near?.let { it.second / it.first.radius } ?: 0.0))
                }
                column++
            }
            row++
        }
        out
    }

    /** The dots of a shoulder (tier 0) or a trigger (tier 1), side -1 left and 1 right. */
    fun shoulder(side: Double, tier: Double): List<Point> = (0 until 9).map { step ->
        val t = step / 8.0
        Point(side * (0.3 + t * 0.34), -0.54 - tier * 0.07 + t * t * 0.1)
    }

    private fun outline(): List<Point> {
        val curves = listOf(
            listOf(150, 44, 270, 44, 308, 52), listOf(352, 58, 372, 110, 392, 190),
            listOf(408, 254, 384, 284, 352, 272), listOf(318, 258, 304, 214, 272, 206),
            listOf(240, 200, 180, 200, 148, 206), listOf(116, 214, 102, 258, 68, 272),
            listOf(36, 284, 12, 254, 28, 190), listOf(48, 110, 68, 58, 112, 52),
        )
        var fromX = 112.0
        var fromY = 52.0
        val points = arrayListOf(Point(fromX, fromY))
        for (c in curves) {
            for (i in 1..24) {
                val t = i / 24.0
                val u = 1 - t
                points.add(Point(
                    u * u * u * fromX + 3 * u * u * t * c[0] + 3 * u * t * t * c[2] + t * t * t * c[4],
                    u * u * u * fromY + 3 * u * u * t * c[1] + 3 * u * t * t * c[3] + t * t * t * c[5],
                ))
            }
            fromX = c[4].toDouble()
            fromY = c[5].toDouble()
        }
        return points
    }

    private fun contains(x: Double, y: Double, polygon: List<Point>): Boolean {
        var inside = false
        var j = polygon.size - 1
        for (i in polygon.indices) {
            val a = polygon[i]
            val b = polygon[j]
            if ((a.y > y) != (b.y > y) && x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x) inside = !inside
            j = i
        }
        return inside
    }
}
