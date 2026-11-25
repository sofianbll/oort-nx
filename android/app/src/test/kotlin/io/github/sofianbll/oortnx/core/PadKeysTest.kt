package io.github.sofianbll.oortnx.core

import android.view.KeyEvent
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PadKeysTest {
    @Test fun aConfirmsAndBGoesBack() {
        assertEquals(Nav.Confirm, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_A, swapAB = false))
        assertEquals(Nav.Back, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_B, swapAB = false))
    }

    @Test fun swappingGivesTheSwitchLayout() {
        assertEquals(Nav.Back, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_A, swapAB = true))
        assertEquals(Nav.Confirm, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_B, swapAB = true))
    }

    @Test fun theSwapNeverTouchesTheKeyboardOrTheDpadCenter() {
        assertEquals(Nav.Confirm, PadKeys.nav(KeyEvent.KEYCODE_ENTER, swapAB = true))
        assertEquals(Nav.Confirm, PadKeys.nav(KeyEvent.KEYCODE_DPAD_CENTER, swapAB = true))
        assertEquals(Nav.Back, PadKeys.nav(KeyEvent.KEYCODE_ESCAPE, swapAB = true))
    }

    @Test fun theSystemBackKeyIsLeftToAndroid() = assertNull(PadKeys.nav(KeyEvent.KEYCODE_BACK, swapAB = false))

    @Test fun shouldersChangeSection() {
        assertEquals(Nav.Previous, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_L1, false))
        assertEquals(Nav.Next, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_R1, false))
    }

    @Test fun theThreeOtherButtonsHaveOnePlaceEach() {
        assertEquals(Nav.Options, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_X, false))
        assertEquals(Nav.Controllers, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_Y, false))
        assertEquals(Nav.Settings, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_START, false))
    }

    @Test fun directionsRoundTrip() {
        for (d in Dir.entries) assertEquals(d, PadKeys.dir(PadKeys.nav(d)))
    }

    // A grid of 7 cells, 3 wide:   0 1 2 / 3 4 5 / 6
    @Test fun focusStaysAtTheEdges() {
        assertEquals(0, gridMove(0, 7, 3, Dir.Left))
        assertEquals(0, gridMove(0, 7, 3, Dir.Up))
        assertEquals(2, gridMove(2, 7, 3, Dir.Right))
        assertEquals(6, gridMove(6, 7, 3, Dir.Right))
        assertEquals(6, gridMove(6, 7, 3, Dir.Down))
    }

    @Test fun focusMovesOneCellOrOneRow() {
        assertEquals(1, gridMove(0, 7, 3, Dir.Right))
        assertEquals(3, gridMove(0, 7, 3, Dir.Down))
        assertEquals(4, gridMove(1, 7, 3, Dir.Down))
        assertEquals(6, gridMove(3, 7, 3, Dir.Down))
        assertEquals(3, gridMove(6, 7, 3, Dir.Up))
    }

    @Test fun anEmptyOrShrunkGridIsSafe() {
        assertEquals(0, gridMove(5, 0, 3, Dir.Down))
        assertEquals(2, gridMove(9, 3, 3, Dir.Right)) // an old focus past the end lands on the last cell
    }
}
