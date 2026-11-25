package io.github.sofianbll.oortnx.core

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** What Oort Cloud says, to draw it. */
class CloudState(
    val stage: String, val hosts: List<String>, val wifiOnly: Boolean, val free: Long, val used: Long, val looking: Boolean, val listed: Boolean,
    val problem: String?, val network: String, val installing: String?, val message: String?,
    val games: List<CloudGame>, val others: List<CloudOther>, val found: Int,
) {
    val isOn get() = stage != "off"
    val hasFilter get() = stage == "ready" || stage == "signIn"
}

class CloudJob(val state: String, val reason: String?, val needed: Long?, val received: Long)
class CloudGame(
    val title: String, val name: String, val version: String, val bytes: Long, val system: String, val packageName: String?, val installed: Boolean,
    val here: String?, val left: Boolean, val job: CloudJob?,
)
class CloudOther(val id: String, val name: String, val reason: String)

/**
 * Oort Cloud, an app of its own: it holds the network, the camera and the installer, so this one holds none of them. It is asked only when it is
 * here and signed with this app's own key, and it answers nobody else.
 */
class CloudClient(private val context: Context, private val changed: (CloudState?) -> Unit) {
    private val main = Handler(Looper.getMainLooper())
    private val work = Executors.newSingleThreadExecutor()
    @Volatile private var pending = false
    private var watching = false
    private val observer = object : ContentObserver(main) {
        override fun onChange(self: Boolean) = read()
    }

    val isHere: Boolean get() = context.packageManager.checkSignatures(context.packageName, MODULE) == PackageManager.SIGNATURE_MATCH

    /** While this app is in front. */
    fun start() {
        if (!isHere) return changed(null)
        if (!watching) context.contentResolver.registerContentObserver(URI, true, observer)
        watching = true
        read()
    }

    fun stop() {
        if (watching) context.contentResolver.unregisterContentObserver(observer)
        watching = false
    }

    /** Many changes make one reading. */
    private fun read() {
        if (pending) return
        pending = true
        work.execute {
            pending = false
            ask("state", null)
        }
    }

    fun call(method: String, arg: String? = null, then: (String?) -> Unit = {}) {
        work.execute {
            val result = ask(method, arg)
            main.post { then(result) }
        }
    }

    private fun ask(method: String, arg: String?): String? {
        if (!isHere) { main.post { changed(null) }; return null }
        val answer: Bundle = try {
            context.contentResolver.call(URI, method, arg, Bundle().apply { putString("language", context.resources.configuration.locales[0].toLanguageTag()) }) ?: return null
        } catch (_: RuntimeException) {
            return null
        }
        val state = answer.getString("state")?.let { parse(it) }
        main.post { if (state != null) changed(state) }
        return answer.getString("result")
    }

    companion object {
        const val MODULE = "io.github.sofianbll.oortnx.alpha.cloud"
        private val URI: Uri = Uri.Builder().scheme("content").authority(MODULE).path("state").build()

        /** A step only Oort Cloud can take: Android's own questions, the browser, the camera. */
        fun step(action: String, title: String? = null): Intent =
            Intent(action).setClassName(MODULE, "io.github.sofianbll.oortnx.cloud.StepActivity").apply { title?.let { putExtra("title", it) } }

        fun parse(text: String): CloudState {
            val o = JSONObject(text)
            fun JSONObject.word(key: String) = if (isNull(key)) null else getString(key)
            fun JSONArray.objects() = (0 until length()).map { getJSONObject(it) }
            val games = o.getJSONArray("games").objects().map { g ->
                val job = g.optJSONObject("job")?.let { CloudJob(it.getString("state"), it.word("reason"), if (it.isNull("needed")) null else it.getLong("needed"), it.getLong("received")) }
                CloudGame(g.getString("title"), g.getString("name"), g.getString("version"), g.getLong("bytes"), g.getString("system"), g.word("package"),
                    g.getBoolean("installed"), g.word("here"), g.getBoolean("left"), job)
            }
            val hidden = o.getJSONArray("hidden").objects().map { CloudOther("h" + it.getString("title"), it.getString("name"), it.getString("reason")) }
            val titles = games.map { it.title } + hidden.map { it.id.drop(1) }
            // A damaged newest build may hide behind an older one that runs: that game is listed already.
            val problems = o.getJSONArray("problems").objects().filter { it.getString("title") !in titles }.distinctBy { it.getString("title") }
                .map { CloudOther("p" + it.getString("title"), it.getString("name"), if (it.getString("error") == "unsigned") "unsigned" else "damaged") }
            val hosts = o.getJSONArray("hosts")
            return CloudState(
                o.getString("stage"), (0 until hosts.length()).map { hosts.getString(it) }, o.getBoolean("wifiOnly"), o.getLong("free"), o.getLong("used"),
                o.getBoolean("looking"), o.getBoolean("listed"), o.word("problem"), o.getString("network"), o.word("installing"), o.word("message"),
                games, hidden + problems, games.count { it.job == null || o.getBoolean("listed") },
            )
        }
    }
}
