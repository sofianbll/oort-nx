package io.github.sofianbll.oortnx.cloud

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.net.Uri
import android.os.Bundle

/** The only door of this app: Oort NX asks, Oort NX draws. Nobody else is answered. */
class CloudProvider : ContentProvider() {
    private val engine get() = CloudEngine.of(context!!)

    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle {
        // Android vouches for the caller's name; the signature says it is ours.
        if (!CloudGuard.allows(context!!, callingPackage)) throw SecurityException("not Oort NX")
        val answer = Bundle()
        when (method) {
            "state" -> Unit
            "turnOn" -> engine.turnOn()
            "code" -> answer.putString("result", engine.take(arg.orEmpty()))
            "changeCode" -> engine.changeCode()
            "turnOff" -> engine.turnOff(arg == "delete")
            "look" -> engine.look()
            "wifiOnly" -> engine.saveWifiOnly(arg == "yes")
            "pause" -> engine.pause(arg.orEmpty())
            "cancel" -> engine.cancel(arg.orEmpty())
            "clean" -> { engine.installs.clean(arg.orEmpty()); engine.changed() }
            else -> throw IllegalArgumentException(method)
        }
        answer.putString("state", engine.state())
        return answer
    }

    override fun query(uri: Uri, projection: Array<String>?, selection: String?, args: Array<String>?, order: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, args: Array<String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<String>?): Int = 0

    companion object {
        val URI: Uri = Uri.parse("content://io.github.sofianbll.oortnx.alpha.cloud/state")
    }
}
