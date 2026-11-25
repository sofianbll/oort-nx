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

class CreditGroup(val title: Map<String, String>, val credits: List<Credit>)

/** The credits of the Android app: assets/credits.json, copied by scripts/generate_credits.py. */
class Credits(val groups: List<CreditGroup>, val legalTitle: Map<String, String>, val legal: List<Map<String, String>>) {
    companion object {
        private const val SYSTEM = "android"

        fun read(text: String): Credits {
            val data = JSONObject(text)
            val labels = data.getJSONObject("labels")
            val roles = data.getJSONObject("roles")
            val credits = data.getJSONArray("credits").objects().filter { SYSTEM in it.getJSONArray("systems").strings() }
            val groups = data.getJSONArray("categories").objects().map { category ->
                CreditGroup(category.getJSONObject("title").words(), credits.filter { it.getString("category") == category.getString("id") }.map { credit(it, category, roles, labels) })
            }
            val legal = data.getJSONArray("legal").objects().filter { SYSTEM in it.getJSONArray("systems").strings() }.map { it.getJSONObject("text").words() }
            return Credits(groups.filter { it.credits.isNotEmpty() }, labels.getJSONObject("legal").words(), legal)
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
