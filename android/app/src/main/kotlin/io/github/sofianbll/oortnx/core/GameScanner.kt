package io.github.sofianbll.oortnx.core

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.PackageInfo
import android.content.pm.ResolveInfo
import android.os.Build

/**
 * Lists the games nx2android installed. Android 11+ hides other apps unless the manifest says which to see: here
 * the apps that have a launcher activity (what Android's own launcher shows), of which Oort keeps those whose
 * package starts with org.nx2a. It asks for no QUERY_ALL_PACKAGES permission, which needs Google Play's approval
 * and shows every package, and it keeps nothing it sees but the games'.
 */
object GameScanner {
    fun scan(context: Context): List<Game> {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return launchers(pm, intent)
            .map { it.activityInfo }
            .filter { Nx2Android.isGamePackage(it.packageName) }
            .distinctBy { it.packageName }
            .mapNotNull { info ->
                try {
                    val pack = packageInfo(pm, info.packageName)
                    Game(
                        packageName = info.packageName,
                        title = info.applicationInfo?.loadLabel(pm)?.toString() ?: info.packageName,
                        versionName = pack.versionName ?: "",
                        versionCode = pack.longVersionCode,
                        activity = info.name,
                    )
                } catch (_: PackageManager.NameNotFoundException) {
                    null // uninstalled between the query and the read
                }
            }
            .sortedBy { it.title.lowercase() }
    }

    // The flag-object overloads need API 33; this app runs from API 29.
    private fun launchers(pm: PackageManager, intent: Intent): List<ResolveInfo> =
        if (Build.VERSION.SDK_INT >= 33) pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        else @Suppress("DEPRECATION") pm.queryIntentActivities(intent, 0)

    private fun packageInfo(pm: PackageManager, name: String): PackageInfo =
        if (Build.VERSION.SDK_INT >= 33) pm.getPackageInfo(name, PackageManager.PackageInfoFlags.of(0))
        else @Suppress("DEPRECATION") pm.getPackageInfo(name, 0)
}
