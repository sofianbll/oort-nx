package io.github.sofianbll.oortnx.core

import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** When a game was last started from Oort, in the player's words. Oort knows nothing of a game started elsewhere. */
sealed interface LastStart {
    data object Never : LastStart
    data object Today : LastStart
    data object Yesterday : LastStart
    data class Days(val count: Int) : LastStart
    data class OnDate(val millis: Long) : LastStart

    companion object {
        fun of(millis: Long?, now: Long, zone: ZoneId): LastStart {
            if (millis == null || millis <= 0) return Never
            val days = ChronoUnit.DAYS.between(Instant.ofEpochMilli(millis).atZone(zone).toLocalDate(), Instant.ofEpochMilli(now).atZone(zone).toLocalDate())
            return when {
                days <= 0 -> Today // also a clock that went back
                days == 1L -> Yesterday
                days <= 30 -> Days(days.toInt())
                else -> OnDate(millis)
            }
        }
    }
}

/** The last started first, the rest by name: [games] comes sorted by name. */
fun lastStartedFirst(games: List<Game>, started: Map<String, Long>): List<Game> = games.sortedByDescending { started[it.packageName] ?: 0L }
