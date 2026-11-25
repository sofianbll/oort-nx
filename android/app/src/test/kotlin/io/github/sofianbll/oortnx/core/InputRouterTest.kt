package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals

class InputRouterTest {
    @Test fun losingWindowFocusDropsAStickAndItsHighlightedButtonsWithoutPausing() {
        val nav = mutableListOf<Nav>()
        var cleared = 0
        val router = InputRouter(swapAB = { false }, sink = { nav.add(it) }, clearHeld = { cleared++ })
        router.stick(1f, 0f, PadSource.LeftStick)
        router.windowFocusChanged(false)
        router.poll(Long.MAX_VALUE)
        assertEquals(listOf(Nav.Right), nav)
        assertEquals(1, cleared)
        router.windowFocusChanged(true)
        router.stick(1f, 0f, PadSource.LeftStick)
        assertEquals(listOf(Nav.Right, Nav.Right), nav)
    }
}
