package io.github.sofianbll.oortnx.core

import java.text.Normalizer
import java.util.Locale

private val MARKS = Regex("\\p{Mn}+")
private const val MAX_QUERY_LENGTH = 256  // UTF-16 units; Android keeps the query in its saved-state Bundle.

internal fun boundedQuery(text: String): String {
    if (text.length <= MAX_QUERY_LENGTH) return text
    val cutsPair = text[MAX_QUERY_LENGTH - 1].isHighSurrogate() && text[MAX_QUERY_LENGTH].isLowSurrogate()
    return text.take(if (cutsPair) MAX_QUERY_LENGTH - 1 else MAX_QUERY_LENGTH)
}

private fun plain(text: String) = Normalizer.normalize(text, Normalizer.Form.NFD).replace(MARKS, "").lowercase(Locale.ROOT)

/** Whether [title] holds every word of [query], whatever the case and the accents. An empty query holds everywhere. */
fun matches(title: String, query: String): Boolean {
    val said = plain(title)
    return plain(query).split(' ').all { it in said }
}
