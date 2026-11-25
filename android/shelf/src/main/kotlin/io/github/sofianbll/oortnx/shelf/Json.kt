package io.github.sofianbll.oortnx.shelf

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException

/** A strict JSON reader for text from outside: UTF-8 only, no repeated key, no deep nesting. Whole numbers are Long. */
class Json private constructor(private val text: String) {
    private var at = 0

    private fun value(depth: Int): Any? {
        if (depth > 32) refuse()
        space()
        return when (peek()) {
            '{' -> {
                at++
                val map = LinkedHashMap<String, Any?>()
                list('}') {
                    space()
                    val key = string()
                    space()
                    expect(':')
                    if (map.containsKey(key)) refuse()
                    map[key] = value(depth + 1)
                }
                map
            }
            '[' -> {
                at++
                val items = ArrayList<Any?>()
                list(']') { items.add(value(depth + 1)) }
                items
            }
            '"' -> string()
            't' -> word("true", true)
            'f' -> word("false", false)
            'n' -> word("null", null)
            else -> number()
        }
    }

    private fun list(end: Char, item: () -> Unit) {
        space()
        if (peek() == end) {
            at++
            return
        }
        while (true) {
            item()
            space()
            if (peek() == ',') at++ else break
        }
        expect(end)
    }

    private fun string(): String {
        expect('"')
        val out = StringBuilder()
        while (true) {
            val c = next()
            when {
                c == '"' -> return out.toString().also { if (!isWhole(it)) refuse() }
                c == '\\' -> when (next()) {
                    '"' -> out.append('"')
                    '\\' -> out.append('\\')
                    '/' -> out.append('/')
                    'b' -> out.append('\b')
                    'f' -> out.append('\u000C')
                    'n' -> out.append('\n')
                    'r' -> out.append('\r')
                    't' -> out.append('\t')
                    'u' -> {
                        if (at + 4 > text.length) refuse()
                        val digits = text.substring(at, at + 4)
                        if (!digits.all { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }) refuse()
                        out.append(digits.toInt(16).toChar())
                        at += 4
                    }
                    else -> refuse()
                }
                c < ' ' -> refuse()
                else -> out.append(c)
            }
        }
    }

    /** No half of a surrogate pair. */
    private fun isWhole(s: String): Boolean {
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c.isHighSurrogate()) {
                if (i + 1 >= s.length || !s[i + 1].isLowSurrogate()) return false
                i++
            } else if (c.isLowSurrogate()) return false
            i++
        }
        return true
    }

    private fun number(): Any {
        val start = at
        while (at < text.length && (text[at].isDigit() || text[at] in "+-.eE")) at++
        val digits = text.substring(start, at)
        if (!NUMBER.matches(digits)) refuse()
        return digits.toLongOrNull() ?: digits.toDoubleOrNull() ?: refuse()
    }

    private fun word(word: String, value: Any?): Any? {
        if (!text.startsWith(word, at)) refuse()
        at += word.length
        return value
    }

    private fun space() {
        while (at < text.length && text[at] in " \t\r\n") at++
    }

    private fun peek(): Char = if (at < text.length) text[at] else refuse()
    private fun next(): Char = peek().also { at++ }
    private fun expect(c: Char) {
        if (next() != c) refuse()
    }

    private fun refuse(): Nothing = throw IllegalArgumentException("not JSON")

    companion object {
        private val NUMBER = Regex("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")

        /** Null when this is not one JSON value. */
        fun read(data: ByteArray): Any? = try {
            val text = Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(data)).toString()
            Json(text).run {
                value(0).also {
                    space()
                    if (at != text.length) refuse()
                }
            }
        } catch (_: IllegalArgumentException) {
            null
        } catch (_: CharacterCodingException) {
            null
        }
    }
}

@Suppress("UNCHECKED_CAST")
fun Any?.jsonObject(): Map<String, Any?>? = this as? Map<String, Any?>
