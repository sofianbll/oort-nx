package io.github.sofianbll.oortnx.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CloudLayoutTest {
    @Test fun aWideWindowFollowsTheMac() {
        val l = CloudLayout.of(1920f, 1080f)
        assertEquals(0.71f * 1920f, l.centreX)
        assertEquals(540f, l.centreY)
        assertEquals(540f, l.radius)
        assertEquals(1080f, l.unit)
    }

    @Test fun theLeftOfAWideWindowIsQuietAndTheRightIsOpen() {
        val l = CloudLayout.of(1920f, 1080f)
        assertEquals(0.10f, l.calm(100f, 500f), 1e-6f)
        assertEquals(1.0f, l.calm(1800f, 500f), 1e-6f)
    }

    @Test fun anUprightWindowPutsTheCloudAboveTheGames() {
        val l = CloudLayout.of(1080f, 2400f)
        assertEquals(540f, l.centreX)
        assertTrue(l.centreY < 2400f * 0.4f)
        assertTrue(l.radius <= 0.46f * 1080f)
        assertEquals(1.0f, l.calm(540f, 600f), 1e-6f)
        assertEquals(0.12f, l.calm(540f, 2300f), 1e-6f)
    }

    @Test fun theSwitchHappensAtTheStatedAspect() {
        assertEquals(0.5f * 1000f, CloudLayout.of(1000f, 1000f).centreX) // upright layout centres horizontally
        assertEquals(0.71f * 1200f, CloudLayout.of(1200f, 1000f).centreX, 1e-3f)
    }
}
