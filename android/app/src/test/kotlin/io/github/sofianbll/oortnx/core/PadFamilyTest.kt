package io.github.sofianbll.oortnx.core

import android.view.KeyEvent
import kotlin.test.Test
import kotlin.test.assertEquals

class PadFamilyTest {
    private val xbox = PadFamily.of(0x045E, 0x0B12, "Xbox Wireless Controller")
    private val sony = PadFamily.of(0x054C, 0x0CE6, "DualSense Wireless Controller")
    private val pro = PadFamily.of(0x057E, 0x2009, "Pro Controller")
    private val joyCon = PadFamily.of(0x057E, 0x2007, "Joy-Con (R)")

    @Test fun theMakerOrTheNameGivesTheFamily() {
        assertEquals(PadFamily.Marks.Xbox, xbox.marks)
        assertEquals(PadFamily.Marks.PlayStation, sony.marks)
        assertEquals(PadFamily.Marks.Nintendo, pro.marks)
        assertEquals(PadFamily.Marks.PlayStation, PadFamily.of(0x1234, 1, "DualShock clone").marks)
        // A pad that only says "Switch" keeps Android's places: its key layout is the generic one.
        assertEquals(PadFamily.Marks.Generic, PadFamily.of(0x2DC8, 1, "Pro Controller for Switch").marks)
    }

    @Test fun eachFamilyHasItsMarks() {
        val bottom = KeyEvent.KEYCODE_BUTTON_A
        assertEquals("A", xbox.mark(bottom))
        assertEquals("✕", sony.mark(bottom))
        assertEquals("□", sony.mark(KeyEvent.KEYCODE_BUTTON_X))
        assertEquals("LB", xbox.mark(KeyEvent.KEYCODE_BUTTON_L1))
        assertEquals("L", pro.mark(KeyEvent.KEYCODE_BUTTON_L1))
        assertEquals("+", pro.mark(KeyEvent.KEYCODE_BUTTON_START))
        assertEquals("Options", sony.mark(KeyEvent.KEYCODE_BUTTON_START))
        assertEquals("☰", xbox.mark(KeyEvent.KEYCODE_BUTTON_START))
    }

    @Test fun thePrintedAConfirmsOnEveryPad() {
        // Android calls Nintendo's right button, printed A, BUTTON_B.
        assertEquals(Nav.Confirm, PadKeys.nav(pro.printed(KeyEvent.KEYCODE_BUTTON_B), swapAB = false))
        assertEquals(Nav.Back, PadKeys.nav(pro.printed(KeyEvent.KEYCODE_BUTTON_A), swapAB = false))
        assertEquals(Nav.Confirm, PadKeys.nav(xbox.printed(KeyEvent.KEYCODE_BUTTON_A), swapAB = false))
        assertEquals(Nav.Confirm, PadKeys.nav(sony.printed(KeyEvent.KEYCODE_BUTTON_A), swapAB = false))
    }

    @Test fun xAndYFollowTheLettersTooByTheProControllersLayoutOnly() {
        assertEquals(Nav.Details, PadKeys.nav(pro.printed(KeyEvent.KEYCODE_BUTTON_Y), swapAB = false)) // the top button, printed X
        assertEquals(KeyEvent.KEYCODE_BUTTON_X, joyCon.printed(KeyEvent.KEYCODE_BUTTON_X))
        assertEquals(KeyEvent.KEYCODE_BUTTON_B, joyCon.printed(KeyEvent.KEYCODE_BUTTON_A))
    }
}
