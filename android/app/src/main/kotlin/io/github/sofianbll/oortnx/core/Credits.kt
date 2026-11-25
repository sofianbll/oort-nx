package io.github.sofianbll.oortnx.core

import org.json.JSONArray
import org.json.JSONObject

/** One project Oort NX owes something to, as design/credits.json lists it for every system. */
class Credit(
    val id: String,
    val name: String,
    /** Author and licence in each language, the second line of every card. */
    val byline: Map<String, String>,
    val role: Map<String, String>,
    val url: String,
    val glyph: String,
    /** The picture that may be shown for it, if any. */
    val picture: String?,
)

class CreditGroup(val id: String, val title: Map<String, String>, val credits: List<Credit>)

/** The credits of the Android app: assets/credits.json, copied by scripts/generate_credits.py. */
class Credits(
    /** The cards every system shows first, in this order, whatever it uses of them. */
    val base: CreditGroup,
    /** The title of the groups. */
    val all: Map<String, String>,
    val groups: List<CreditGroup>,
    val legalTitle: Map<String, String>,
    val legal: List<Map<String, String>>,
) {
    companion object {
        private const val SYSTEM = "android"

        fun read(text: String): Credits {
            val data = JSONObject(text)
            val labels = data.getJSONObject("labels")
            val roles = data.getJSONObject("roles")
            val all = data.getJSONArray("credits").objects()
            val base = data.getJSONArray("base").strings()
            val categories = data.getJSONArray("categories").objects()
            fun group(category: JSONObject, own: List<JSONObject>) =
                CreditGroup(category.getString("id"), category.getJSONObject("title").words(), own.map { credit(it, category, roles, labels) })
            val first = base.map { id -> all.first { it.getString("id") == id } }
            val credits = all.filter { it.getString("id") !in base && SYSTEM in it.getJSONArray("systems").strings() }
            val groups = categories.map { category -> group(category, credits.filter { it.getString("category") == category.getString("id") }) }
            val legal = data.getJSONArray("legal").objects().filter { SYSTEM in it.getJSONArray("systems").strings() }.map { it.getJSONObject("text").words() }
            return Credits(
                group(categories.first { it.getString("id") == first[0].getString("category") }, first),
                labels.getJSONObject("all").words(), groups.filter { it.credits.isNotEmpty() }, labels.getJSONObject("legal").words(), legal,
            )
        }

        private fun credit(item: JSONObject, category: JSONObject, roles: JSONObject, labels: JSONObject): Credit {
            val name = item.getString("name")
            val author = item.getString("author")
            // A service has an owner, not a licence.
            val stands = labels.getJSONObject(if (item.getString("use") == "service") "online" else "unlisted").words()
            val terms = if (item.isNull("license")) stands else stands.mapValues { item.getString("license") }
            val icon = item.optJSONObject("icon")
            return Credit(
                item.getString("id"), name, if (author == name) terms else terms.mapValues { "$author · ${it.value}" },
                roles.getJSONObject(item.getString("role")).words(), item.getString("url"),
                item.optString("glyph").ifEmpty { category.getString("glyph") },
                icon?.takeIf { it.optBoolean("allowed") }?.optString("asset"),
            )
        }

        private fun JSONArray.objects() = List(length()) { getJSONObject(it) }
        private fun JSONArray.strings() = List(length()) { getString(it) }
        private fun JSONObject.words() = keys().asSequence().associateWith { getString(it) }
    }
}
