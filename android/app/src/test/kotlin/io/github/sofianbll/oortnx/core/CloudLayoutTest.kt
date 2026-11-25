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

    @Test fun anUprightWindowShowsTheCloudFromTheRightAsThePhoneAppDoes() {
        val l = CloudLayout.of(1000f, 2200f)
        assertEquals(1500f, l.unit)
        assertEquals(750f, l.centreY)
        assertEquals(795f, l.centreX, 1f)
        assertTrue(l.centreX + l.radius > 1000f) // it runs off the right edge
    }

    @Test fun theFootOfAnUprightWindowIsEmpty() {
        val l = CloudLayout.of(1000f, 2200f)
        assertEquals(0f, l.calm(900f, 1500f), 1e-6f)
        assertEquals(1f, l.calm(900f, 900f), 1e-6f)
    }

    @Test fun theLayoutDoesNotJumpBetweenTheTwoShapes() {
        val wide = CloudLayout.of(1001f, 1000f)
        val tall = CloudLayout.of(999f, 1000f)
        assertEquals(wide.centreX, tall.centreX, 3f)
        assertEquals(wide.radius, tall.radius, 3f)
    }
}
