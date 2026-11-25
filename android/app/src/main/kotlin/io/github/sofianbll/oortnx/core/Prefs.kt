package io.github.sofianbll.oortnx.core

import android.content.Context
import android.content.SharedPreferences
import android.provider.Settings
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** The launcher's few settings, kept on the device and nowhere else. */
class Prefs(context: Context) {
    private val store: SharedPreferences = context.getSharedPreferences("oort", Context.MODE_PRIVATE)

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
    private val systemCalm: Boolean =
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f

    val calm: Boolean get() = calmChoice ?: systemCalm

    fun saveSound(on: Boolean) { sound = on; store.edit().putBoolean("sound", on).apply() }
    fun savePack(name: String) { if (name in OortSynth.packs) { pack = name; store.edit().putString("pack", name).apply() } }
    fun saveSwapAB(on: Boolean) { swapAB = on; store.edit().putBoolean("swapAB", on).apply() }
    fun saveCalm(on: Boolean) { calmChoice = on; store.edit().putBoolean("calm", on).apply() }
}
