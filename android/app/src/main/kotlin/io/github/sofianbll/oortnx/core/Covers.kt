package io.github.sofianbll.oortnx.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.util.DisplayMetrics
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap

/** A game's cover: its own app icon, in the sharpest size it ships, as a full square (no launcher mask). */
object Covers {
    private const val SIDE = 512

    fun of(context: Context, game: Game): ImageBitmap? = try {
        val pm = context.packageManager
        val info = pm.getApplicationInfo(game.packageName, 0)
        val sharp = if (info.icon != 0) pm.getResourcesForApplication(info).getDrawableForDensity(info.icon, DisplayMetrics.DENSITY_XXXHIGH, null) else null
        draw(sharp ?: pm.getApplicationIcon(info))
    } catch (_: Exception) {
        null // a demo entry, a package that went away, or an icon that cannot be read: the tile shows the game's letter
    }

    private fun draw(icon: Drawable): ImageBitmap {
        val bitmap = Bitmap.createBitmap(SIDE, SIDE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        if (icon is AdaptiveIconDrawable) {
            // Its layers are 108 wide for 72 seen: the rest runs off the square.
            val over = SIDE / 4
            for (layer in listOfNotNull(icon.background, icon.foreground)) {
                layer.setBounds(-over, -over, SIDE + over, SIDE + over)
                layer.draw(canvas)
            }
        } else {
            icon.setBounds(0, 0, SIDE, SIDE)
            icon.isFilterBitmap = true
            icon.draw(canvas)
        }
        return bitmap.asImageBitmap()
    }
}
