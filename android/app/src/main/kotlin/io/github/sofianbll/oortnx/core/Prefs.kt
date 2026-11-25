package io.github.sofianbll.oortnx.core

import android.content.Context
import android.content.SharedPreferences
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** The launcher's few settings, kept on the device and nowhere else. */
class Prefs internal constructor(
    private val store: SharedPreferences,
    private val system: () -> Pair<Boolean, Boolean>,
) {
    constructor(context: Context) : this(context.getSharedPreferences("oort", Context.MODE_PRIVATE), {
        val noAnimations = Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
        val saving = (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isPowerSaveMode == true
        noAnimations to saving
    })

    var sound by mutableStateOf(store.getBoolean("sound", true))
        private set
    var pack by mutableStateOf(store.getString("pack", "oort")?.takeIf { it in OortSynth.packs } ?: "oort")
        private set
    var swapAB by mutableStateOf(store.getBoolean("swapAB", false))
        private set

    /** Null follows Android's "remove animations" switch; true or false is the player's own choice. */
    var calmChoice by mutableStateOf(if (store.contains("calm")) store.getBoolean("calm", false) else null)
        private set

    // The system switch sets the animator scale to 0 (Settings > Accessibility > Remove animations).
    private var noAnimations by mutableStateOf(false)
    private var saving by mutableStateOf(false)

    /** Nothing moves: the player asked for it here, or Android's "remove animations" is on. */
    val calm: Boolean get() = calmChoice ?: noAnimations

    /** The cloud also rests while Android saves the battery. */
    val stillCloud: Boolean get() = calm || saving

    /** The library in order of name; else the last started first. */
    var byName by mutableStateOf(store.getBoolean("byName", false))
        private set

    /** The favourites, by package. */
    var favorites by mutableStateOf(store.getStringSet("favorites", emptySet()).orEmpty().toSet())
        private set

    /** When each game was last started from here, by package. */
    var started by mutableStateOf(store.all.filterKeys { it.startsWith(STARTED) }.mapNotNull { (k, v) -> (v as? Long)?.let { k.removePrefix(STARTED) to it } }.toMap())
        private set

    init { refresh() }

    /** Reads Android's own switches again: they change while the app is behind. */
    fun refresh() {
        val (removeAnimations, savingPower) = system()
        noAnimations = removeAnimations
        saving = savingPower
    }

    fun saveByName(on: Boolean) { byName = on; store.edit().putBoolean("byName", on).apply() }
    fun saveStarted(packageName: String, at: Long) { started = started + (packageName to at); store.edit().putLong(STARTED + packageName, at).apply() }

    fun saveFavorite(packageName: String, on: Boolean) {
        favorites = if (on) favorites + packageName else favorites - packageName
        store.edit().putStringSet("favorites", favorites).apply()
    }
    fun saveSound(on: Boolean) { sound = on; store.edit().putBoolean("sound", on).apply() }
    fun savePack(name: String) { if (name in OortSynth.packs) { pack = name; store.edit().putString("pack", name).apply() } }
    fun saveSwapAB(on: Boolean) { swapAB = on; store.edit().putBoolean("swapAB", on).apply() }
    fun saveCalm(on: Boolean) { calmChoice = on; store.edit().putBoolean("calm", on).apply() }

    private companion object { const val STARTED = "started:" }
}
