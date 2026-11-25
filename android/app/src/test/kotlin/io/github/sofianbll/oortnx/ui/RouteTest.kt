package io.github.sofianbll.oortnx.ui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class RouteTest {
    @Test fun everyPageSurvivesBeingKept() {
        val pages = listOf(Route.GamePage("org.nx2a.testmaree"), Route.PadTest, Route.Sounds, Route.Buttons, Route.Cloud, Route.WhichGames, Route.Thanks) +
            LicenceText.entries.map { Route.Licence(it) }
        for (page in pages) assertEquals(page, routeOf(page.saved))
    }

    @Test fun anUnknownWordIsNoPage() {
        assertNull(routeOf("gone"))
        assertNull(routeOf("licence:gone"))
    }
}
