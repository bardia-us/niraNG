package dev.nirang.client.subscription

import org.json.JSONObject

/** Android's JSON parser accepts non-JSON syntax. Validate before decoding,
 * including duplicate (decoded) keys, so PHP/native cores cannot disagree. */
internal object StrictProfileJson {
    fun objectValue(text: String, maxBytes: Int): JSONObject {
        require(text.toByteArray(Charsets.UTF_8).size <= maxBytes) { "Profile JSON exceeds size limit" }
        Scanner(text).validate()
        return try { JSONObject(text) } catch (_: Exception) { throw IllegalArgumentException("Profile must be a JSON object") }
    }

    private class Scanner(val text: String) {
        var i = 0
        fun invalid(): Nothing = throw IllegalArgumentException("Invalid profile JSON")
        fun whitespace() { while (i < text.length && text[i] in " \t\r\n") i++ }
        fun take(c: Char): Boolean { whitespace(); if (i < text.length && text[i] == c) { i++; return true }; return false }
        fun validate() { value(0); whitespace(); if (i != text.length) invalid() }
        fun value(depth: Int) {
            if (depth > 64) invalid()
            whitespace()
            if (i >= text.length) invalid()
            when (text[i]) {
                '{' -> {
                    i++; val keys = hashSetOf<String>()
                    if (take('}')) return
                    do { whitespace(); val key = string(); if (!keys.add(key) || !take(':')) invalid(); value(depth + 1) } while (take(','))
                    if (!take('}')) invalid()
                }
                '[' -> {
                    i++; if (take(']')) return
                    do { value(depth + 1) } while (take(','))
                    if (!take(']')) invalid()
                }
                '"' -> string()
                't' -> literal("true")
                'f' -> literal("false")
                'n' -> literal("null")
                else -> number()
            }
        }
        fun literal(token: String) { if (!text.startsWith(token, i)) invalid(); i += token.length }
        fun number() {
            val start = i
            if (i < text.length && text[i] == '-') i++
            if (i >= text.length) invalid()
            if (text[i] == '0') i++ else {
                if (text[i] !in '1'..'9') invalid()
                while (i < text.length && text[i] in '0'..'9') i++
            }
            if (i < text.length && text[i] == '.') { i++; digits() }
            if (i < text.length && text[i] in "eE") { i++; if (i < text.length && text[i] in "+-") i++; digits() }
            if (start == i) invalid()
        }
        fun digits() { val start = i; while (i < text.length && text[i] in '0'..'9') i++; if (start == i) invalid() }
        fun string(): String {
            if (i >= text.length || text[i++] != '"') invalid()
            val out = StringBuilder()
            while (i < text.length) {
                var c = text[i++]
                if (c == '"') {
                    val result = out.toString()
                    var p = 0
                    while (p < result.length) {
                        val ch = result[p++]
                        if (Character.isHighSurrogate(ch)) {
                            if (p >= result.length || !Character.isLowSurrogate(result[p++])) invalid()
                        } else if (Character.isLowSurrogate(ch)) invalid()
                    }
                    return result
                }
                if (c.code < 32) invalid()
                if (c == '\\') {
                    if (i >= text.length) invalid()
                    c = when (val escape = text[i++]) {
                        '"', '\\', '/' -> escape
                        'b' -> '\b'; 'f' -> '\u000C'; 'n' -> '\n'; 'r' -> '\r'; 't' -> '\t'
                        'u' -> { if (i + 4 > text.length) invalid(); val hex = text.substring(i, i + 4); if (hex.any { it !in "0123456789abcdefABCDEF" }) invalid(); i += 4; hex.toInt(16).toChar() }
                        else -> invalid()
                    }
                }
                out.append(c)
            }
            invalid()
        }
    }
}
