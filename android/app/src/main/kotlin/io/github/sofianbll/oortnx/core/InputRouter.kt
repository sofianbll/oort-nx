package io.github.sofianbll.oortnx.core

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent

/**
 * Turns what a controller or a keyboard does into [Nav] events: buttons, the D-pad (as keys or as a hat axis) and both
 * sticks, with the repeat of a held direction shared between them ([DirectionRepeat], as on the Mac).
 * The activity feeds it from dispatchKeyEvent and dispatchGenericMotionEvent, then calls [poll] on a timer.
 */
class InputRouter(
    private val swapAB: () -> Boolean,
    private val sink: (Nav) -> Unit,
) {
    private val repeat = DirectionRepeat()
    private var lastMove = 0L
    private var hatX = 0
    private var hatY = 0

    fun key(event: KeyEvent): Boolean {
        val nav = PadKeys.nav(event.keyCode, swapAB()) ?: return false
        val dir = PadKeys.dir(nav)
        if (event.action == KeyEvent.ACTION_DOWN) {
            if (event.repeatCount == 0) {
                if (dir == null) sink(nav)
                else if (repeat.press(dir, PadSource.Pad)) { lastMove = System.nanoTime(); sink(nav) }
            }
        } else if (event.action == KeyEvent.ACTION_UP && dir != null) {
            repeat.release(dir, PadSource.Pad)
        }
        return true // the repeat is ours: Android's key repeat would move twice
    }

    fun motion(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK || event.action != MotionEvent.ACTION_MOVE) return false
        // The D-pad of many controllers is a hat axis: -1 left or up, +1 right or down.
        val x = event.getAxisValue(MotionEvent.AXIS_HAT_X).let { if (it < -0.5f) -1 else if (it > 0.5f) 1 else 0 }
        val y = event.getAxisValue(MotionEvent.AXIS_HAT_Y).let { if (it < -0.5f) -1 else if (it > 0.5f) 1 else 0 }
        hat(x, hatX, Dir.Left, Dir.Right); hatX = x
        hat(y, hatY, Dir.Up, Dir.Down); hatY = y
        stick(event.getAxisValue(MotionEvent.AXIS_X), -event.getAxisValue(MotionEvent.AXIS_Y), PadSource.LeftStick)
        stick(event.getAxisValue(MotionEvent.AXIS_Z), -event.getAxisValue(MotionEvent.AXIS_RZ), PadSource.RightStick)
        return true
    }

    private fun hat(now: Int, before: Int, negative: Dir, positive: Dir) {
        if (now == before) return
        if (before < 0) repeat.release(negative, PadSource.Pad)
        if (before > 0) repeat.release(positive, PadSource.Pad)
        val next = if (now < 0) negative else if (now > 0) positive else return
        if (repeat.press(next, PadSource.Pad)) { lastMove = System.nanoTime(); sink(PadKeys.nav(next)) }
    }

    private fun stick(x: Float, y: Float, source: PadSource) {
        repeat.stick(x, y, STICK_DEADZONE, source)?.let { lastMove = System.nanoTime(); sink(PadKeys.nav(it)) }
    }

    /** Call about every 20 ms: the next step of a held direction, when its turn has come. */
    fun poll(now: Long = System.nanoTime()) {
        val held = repeat.current ?: return
        if ((now - lastMove) / 1e9 < repeat.nextDelay) return
        lastMove = now
        repeat.tick()
        sink(PadKeys.nav(held))
    }

    /** A pad that goes away must not leave a direction held. */
    fun reset() {
        repeat.reset()
        hatX = 0
        hatY = 0
    }

    private companion object {
        const val STICK_DEADZONE = 0.55f
    }
}
