package io.github.sofianbll.oortnx.core

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings

/**
 * What a third-party launcher can do with an nx2android game, and nothing more: nx2android's app is a
 * NativeActivity with an exported MAIN/LAUNCHER activity, reads no intent extra, and keeps its files in
 * Android/data, which no other app can open (see android/README.md).
 */
object GameLauncher {
    /** Starts the game. False when Android refused (the package went away, or has no launcher activity). */
    fun play(context: Context, game: Game): Boolean {
        val target = game.activity ?: return false
        val intent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
            .setComponent(ComponentName(game.packageName, target))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return start(context, intent)
    }

    /**
     * Android's own page for the app: storage, permissions, force stop, and Uninstall. Asking Android to uninstall
     * directly (ACTION_DELETE) needs REQUEST_DELETE_PACKAGES since API 28, and this app asks for no permission.
     */
    fun appInfo(context: Context, game: Game): Boolean =
        start(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${game.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    private fun start(context: Context, intent: Intent): Boolean = try {
        context.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}
