package io.github.sofianbll.oortnx.core

import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals

class LastStartTest {
    private val paris = ZoneId.of("Europe/Paris")
    private fun at(day: Int, hour: Int, month: Int = 3) = LocalDateTime.of(2026, month, day, hour, 30).atZone(paris).toInstant().toEpochMilli()
    private fun said(then: Long?, now: Long) = LastStart.of(then, now, paris)

    @Test fun daysAreCalendarDaysNotTwentyFourHours() {
        assertEquals(LastStart.Yesterday, said(at(9, 23), at(10, 0)))
        assertEquals(LastStart.Today, said(at(10, 0), at(10, 23)))
    }

    @Test fun aClockChangeDoesNotShiftTheDay() = assertEquals(LastStart.Yesterday, said(at(28, 12), at(29, 12)))

    @Test fun afterAMonthItIsADate() {
        assertEquals(LastStart.Days(30), said(at(1, 12), at(31, 12)))
        assertEquals(LastStart.OnDate(at(1, 12)), said(at(1, 12), at(1, 12, month = 4)))
    }

    @Test fun neverAndAFutureDateAreSafe() {
        assertEquals(LastStart.Never, said(null, at(10, 0)))
        assertEquals(LastStart.Today, said(at(11, 0), at(10, 0)))
    }

    @Test fun theLastStartedComesFirstAndTheRestKeepTheirOrder() {
        val games = listOf("a", "b", "c", "d").map { Game(it, it, "1", 1, null) }
        assertEquals(listOf("c", "b", "a", "d"), lastStartedFirst(games, mapOf("b" to 5L, "c" to 9L)).map { it.title })
    }
}
