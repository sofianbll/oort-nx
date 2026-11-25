package io.github.sofianbll.oortnx.core

import java.text.Normalizer
import java.util.Locale

private val MARKS = Regex("\\p{Mn}+")

private fun plain(text: String) = Normalizer.normalize(text, Normalizer.Form.NFD).replace(MARKS, "").lowercase(Locale.ROOT)

/** Whether [title] holds every word of [query], whatever the case and the accents. An empty query holds everywhere. */
fun matches(title: String, query: String): Boolean {
    val said = plain(title)
    return plain(query).split(' ').all { it in said }
}
