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

    @Test fun theOtherButtonsHaveTheMacsPlaces() {
        assertEquals(Nav.Details, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_X, false))
        assertEquals(Nav.Controllers, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_Y, false))
        assertEquals(Nav.Options, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_START, false))
        assertEquals(Nav.Options, PadKeys.nav(KeyEvent.KEYCODE_MENU, false))
        assertEquals(Nav.Sort, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_THUMBR, false))
        assertEquals(Nav.First, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_L2, false))
        assertEquals(Nav.Last, PadKeys.nav(KeyEvent.KEYCODE_BUTTON_R2, false))
    }

    @Test fun theHomeButtonIsTheSystems() = assertNull(PadKeys.nav(KeyEvent.KEYCODE_BUTTON_MODE, false))

    @Test fun theKeyboardHasTheMacsShortcutsWithControl() {
        assertEquals(Nav.Details, PadKeys.keyboard(KeyEvent.KEYCODE_D, ctrl = true, shift = false))
        assertEquals(Nav.Options, PadKeys.keyboard(KeyEvent.KEYCODE_O, ctrl = true, shift = false))
        assertEquals(Nav.Settings, PadKeys.keyboard(KeyEvent.KEYCODE_COMMA, ctrl = true, shift = false))
        assertNull(PadKeys.keyboard(KeyEvent.KEYCODE_C, ctrl = true, shift = false))
        assertNull(PadKeys.keyboard(KeyEvent.KEYCODE_ENTER, ctrl = true, shift = false))
    }

    @Test fun tabMovesThroughTheSamePlacesAndLettersChangeTab() {
        assertEquals(Nav.Forward, PadKeys.keyboard(KeyEvent.KEYCODE_TAB, ctrl = false, shift = false))
        assertEquals(Nav.Backward, PadKeys.keyboard(KeyEvent.KEYCODE_TAB, ctrl = false, shift = true))
        assertEquals(Nav.Previous, PadKeys.keyboard(KeyEvent.KEYCODE_Q, ctrl = false, shift = false))
        assertEquals(Nav.Next, PadKeys.keyboard(KeyEvent.KEYCODE_E, ctrl = false, shift = false))
        assertEquals(Nav.Confirm, PadKeys.keyboard(KeyEvent.KEYCODE_ENTER, ctrl = false, shift = false))
        assertEquals(Nav.Back, PadKeys.keyboard(KeyEvent.KEYCODE_ESCAPE, ctrl = false, shift = false))
        assertNull(PadKeys.keyboard(KeyEvent.KEYCODE_A, ctrl = false, shift = false))
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
