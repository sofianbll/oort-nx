package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DirectionRepeatTest {
    @Test fun aNewDirectionMovesAtOnceAndAHeldOneDoesNot() {
        val r = DirectionRepeat()
        assertTrue(r.press(Dir.Right, PadSource.Pad))
        assertFalse(r.press(Dir.Right, PadSource.Pad))
        assertEquals(Dir.Right, r.current)
    }

    @Test fun waitsThenRepeatsThenSpeedsUp() {
        val r = DirectionRepeat()
        r.press(Dir.Down, PadSource.Pad)
        assertEquals(DirectionRepeat.FIRST_DELAY, r.nextDelay)
        r.tick()
        assertEquals(DirectionRepeat.INTERVAL, r.nextDelay)
        repeat(7) { r.tick() }
        assertEquals(DirectionRepeat.FAST_INTERVAL, r.nextDelay)
    }

    @Test fun theLastPressedLeadsAndReleasingGivesBackTheOther() {
        val r = DirectionRepeat()
        r.press(Dir.Left, PadSource.Pad)
        r.press(Dir.Up, PadSource.LeftStick)
        assertEquals(Dir.Up, r.current)
        r.release(Dir.Up, PadSource.LeftStick)
        assertEquals(Dir.Left, r.current)
        r.release(Dir.Left, PadSource.Pad)
        assertNull(r.current)
        assertNull(r.tick())
    }

    @Test fun aStickInsideTheDeadzoneDoesNothing() {
        val r = DirectionRepeat()
        assertNull(r.stick(0.2f, 0.1f, 0.55f, PadSource.LeftStick))
    }

    @Test fun aStickPushedRightMovesOnceAndHoldsWithoutChatter() {
        val r = DirectionRepeat()
        assertEquals(Dir.Right, r.stick(0.9f, 0.1f, 0.55f, PadSource.LeftStick))
        // Resting just under the threshold keeps the same direction (slack of 0.8 of the deadzone).
        assertNull(r.stick(0.5f, 0.0f, 0.55f, PadSource.LeftStick))
        assertEquals(Dir.Right, r.current)
        assertNull(r.stick(0.0f, 0.0f, 0.55f, PadSource.LeftStick))
        assertNull(r.current)
    }

    @Test fun theRightStickOnlyMovesUpAndDown() {
        val r = DirectionRepeat()
        assertNull(r.stick(0.9f, 0.0f, 0.55f, PadSource.RightStick))
        assertEquals(Dir.Up, r.stick(0.0f, 0.9f, 0.55f, PadSource.RightStick))
    }

    @Test fun theRightStickRepeatsMoreSlowlyAtFirst() {
        val r = DirectionRepeat()
        r.stick(0.0f, -0.9f, 0.55f, PadSource.RightStick)
        assertEquals(DirectionRepeat.INTERVAL * 1.5, r.nextDelay)
    }
}
