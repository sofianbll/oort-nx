package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals

/** Numbers printed by the Mac's own OortPadShape.swift. */
class PadShapeTest {
    @Test fun theDotsAreTheMacs() {
        assertEquals(1036, PadShape.cells.size)
        assertEquals(155, PadShape.cells.count { it.part != null })
        val first = PadShape.cells.first()
        assertEquals(-0.3947619047619048, first.x, 1e-9)
        assertEquals(-0.4775790476190476, first.y, 1e-9)
        val middle = PadShape.cells[500]
        assertEquals(-0.43380952380952387, middle.x, 1e-9)
        assertEquals(-0.00416571428571439, middle.y, 1e-9)
        val last = PadShape.cells.last()
        assertEquals(0.7961904761904761, last.x, 1e-9)
        assertEquals(0.5706933333333333, last.y, 1e-9)
    }

    @Test fun everyPartHasItsDots() {
        val expected = mapOf(
            PadShape.Place.LeftStick to 44, PadShape.Place.RightStick to 38, PadShape.Place.Up to 6, PadShape.Place.Down to 5,
            PadShape.Place.Left to 7, PadShape.Place.Right to 5, PadShape.Place.Top to 10, PadShape.Place.West to 9,
            PadShape.Place.East to 9, PadShape.Place.Bottom to 10, PadShape.Place.View to 3, PadShape.Place.Menu to 3,
            PadShape.Place.Home to 6,
        )
        assertEquals(expected, PadShape.cells.mapNotNull { it.part }.groupingBy { it }.eachCount())
    }

    @Test fun theShouldersAreTheMacs() {
        val p = PadShape.shoulder(-1.0, 1.0)[4]
        assertEquals(-0.47, p.x, 1e-9)
        assertEquals(-0.585, p.y, 1e-9)
    }
}
