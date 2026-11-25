package io.github.sofianbll.oortnx.core

import android.view.KeyEvent

/** What a button or a direction does in the launcher. */
enum class Nav { Up, Down, Left, Right, Confirm, Back, Previous, Next, Details, Controllers, Options, Sort, First, Last, Forward, Backward, Settings }

/**
 * What a key does. The codes are those of the letters printed on the pad ([PadFamily.printed]): A confirms and B goes
 * back, wherever the maker put them. A player whose pad Android does not know can swap the two in the settings.
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

    /**
     * A real keyboard: arrows, Enter and Escape as above, Tab through the same places, and the Mac's shortcuts with Ctrl
     * for Command. Null leaves the key to Android.
     */
    fun keyboard(keyCode: Int, ctrl: Boolean, shift: Boolean): Nav? = if (ctrl) when (keyCode) {
        KeyEvent.KEYCODE_D -> Nav.Details
        KeyEvent.KEYCODE_O -> Nav.Options
        KeyEvent.KEYCODE_COMMA -> Nav.Settings
        else -> null
    } else when (keyCode) {
        KeyEvent.KEYCODE_TAB -> if (shift) Nav.Backward else Nav.Forward
        KeyEvent.KEYCODE_Q -> Nav.Previous
        KeyEvent.KEYCODE_E -> Nav.Next
        KeyEvent.KEYCODE_X -> Nav.Details
        KeyEvent.KEYCODE_F3 -> Nav.Sort
        KeyEvent.KEYCODE_MOVE_HOME -> Nav.First
        KeyEvent.KEYCODE_MOVE_END -> Nav.Last
        KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT,
        KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_ESCAPE, KeyEvent.KEYCODE_MENU -> nav(keyCode, swapAB = false)
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
