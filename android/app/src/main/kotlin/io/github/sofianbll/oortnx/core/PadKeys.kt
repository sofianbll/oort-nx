package io.github.sofianbll.oortnx.core

import android.view.KeyEvent

/** What a button or a direction does in the launcher. */
enum class Nav { Up, Down, Left, Right, Confirm, Back, Previous, Next, Details, Controllers, Options, Sort, First, Last }

/**
 * Android reports a pad's buttons by label: BUTTON_A is the south button on an Xbox layout, and is what Android's own
 * apps use to confirm. A player who wants the Switch layout (east button confirms) swaps A and B in the settings.
 */
object PadKeys {
    fun nav(keyCode: Int, swapAB: Boolean): Nav? = when (keyCode) {
        KeyEvent.KEYCODE_DPAD_UP -> Nav.Up
        KeyEvent.KEYCODE_DPAD_DOWN -> Nav.Down
        KeyEvent.KEYCODE_DPAD_LEFT -> Nav.Left
        KeyEvent.KEYCODE_DPAD_RIGHT -> Nav.Right
        KeyEvent.KEYCODE_BUTTON_A -> if (swapAB) Nav.Back else Nav.Confirm
        KeyEvent.KEYCODE_BUTTON_B -> if (swapAB) Nav.Confirm else Nav.Back
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> Nav.Confirm
        KeyEvent.KEYCODE_ESCAPE -> Nav.Back
        KeyEvent.KEYCODE_BUTTON_L1 -> Nav.Previous
        KeyEvent.KEYCODE_BUTTON_R1 -> Nav.Next
        // The same places as on the Mac: X the game's page, + (Start, Menu, Options) its options.
        KeyEvent.KEYCODE_BUTTON_X -> Nav.Details
        KeyEvent.KEYCODE_BUTTON_Y -> Nav.Controllers
        KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> Nav.Options
        KeyEvent.KEYCODE_BUTTON_THUMBR -> Nav.Sort
        KeyEvent.KEYCODE_BUTTON_L2 -> Nav.First
        KeyEvent.KEYCODE_BUTTON_R2 -> Nav.Last
        else -> null
    }

    /** The four directions as repeat directions, or null for any other nav. */
    fun dir(nav: Nav): Dir? = when (nav) {
        Nav.Up -> Dir.Up
        Nav.Down -> Dir.Down
        Nav.Left -> Dir.Left
        Nav.Right -> Dir.Right
        else -> null
    }

    fun nav(dir: Dir): Nav = when (dir) {
        Dir.Up -> Nav.Up
        Dir.Down -> Nav.Down
        Dir.Left -> Nav.Left
        Dir.Right -> Nav.Right
    }
}

/** Where focus goes in a grid of [count] cells, [columns] wide, from [index]. Stays put at an edge. */
fun gridMove(index: Int, count: Int, columns: Int, dir: Dir): Int {
    if (count <= 0) return 0
    val here = index.coerceIn(0, count - 1)
    val cols = columns.coerceAtLeast(1)
    val next = when (dir) {
        Dir.Left -> if (here % cols == 0) here else here - 1
        Dir.Right -> if (here % cols == cols - 1 || here == count - 1) here else here + 1
        Dir.Up -> if (here - cols < 0) here else here - cols
        Dir.Down -> if (here + cols > count - 1) here else here + cols
    }
    return next
}
