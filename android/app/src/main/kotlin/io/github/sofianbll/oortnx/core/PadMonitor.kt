package io.github.sofianbll.oortnx.core

import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlin.math.hypot

/** What is held on the controller right now, for the screen that shows it. Android names buttons by label: the places here are the Xbox ones. */
class PadMonitor {
    data class Held(
        val keys: Set<Int> = emptySet(),
        val hatX: Float = 0f, val hatY: Float = 0f,
        val leftX: Float = 0f, val leftY: Float = 0f,
        val rightX: Float = 0f, val rightY: Float = 0f,
        val leftTrigger: Float = 0f, val rightTrigger: Float = 0f,
    ) {
        fun press(place: PadShape.Place): Float = when (place) {
            PadShape.Place.LeftStick -> maxOf(key(KeyEvent.KEYCODE_BUTTON_THUMBL), hypot(leftX, leftY) * 0.6f)
            PadShape.Place.RightStick -> maxOf(key(KeyEvent.KEYCODE_BUTTON_THUMBR), hypot(rightX, rightY) * 0.6f)
            PadShape.Place.Up -> maxOf(key(KeyEvent.KEYCODE_DPAD_UP), -hatY)
            PadShape.Place.Down -> maxOf(key(KeyEvent.KEYCODE_DPAD_DOWN), hatY)
            PadShape.Place.Left -> maxOf(key(KeyEvent.KEYCODE_DPAD_LEFT), -hatX)
            PadShape.Place.Right -> maxOf(key(KeyEvent.KEYCODE_DPAD_RIGHT), hatX)
            PadShape.Place.Top -> key(KeyEvent.KEYCODE_BUTTON_Y)
            PadShape.Place.West -> key(KeyEvent.KEYCODE_BUTTON_X)
            PadShape.Place.East -> key(KeyEvent.KEYCODE_BUTTON_B)
            PadShape.Place.Bottom -> key(KeyEvent.KEYCODE_BUTTON_A)
            PadShape.Place.View -> key(KeyEvent.KEYCODE_BUTTON_SELECT)
            PadShape.Place.Menu -> key(KeyEvent.KEYCODE_BUTTON_START)
            PadShape.Place.Home -> key(KeyEvent.KEYCODE_BUTTON_MODE)
        }

        /** L1, L2, R1, R2, from 0 to 1. */
        val shoulders: List<Float>
            get() = listOf(
                key(KeyEvent.KEYCODE_BUTTON_L1), maxOf(key(KeyEvent.KEYCODE_BUTTON_L2), leftTrigger),
                key(KeyEvent.KEYCODE_BUTTON_R1), maxOf(key(KeyEvent.KEYCODE_BUTTON_R2), rightTrigger),
            )

        /** The bottom or the right button: held, it closes the screen. */
        val closing: Boolean get() = KeyEvent.KEYCODE_BUTTON_A in keys || KeyEvent.KEYCODE_BUTTON_B in keys

        private fun key(code: Int) = if (code in keys) 1f else 0f
    }

    var held by mutableStateOf(Held())
        private set

    /** The last button pressed, as Android names it (its place on an Xbox pad). */
    var lastKey by mutableStateOf<Int?>(null)
        private set

    /** True when the key is a controller's: the caller may keep it from the rest of the app. */
    fun key(event: KeyEvent): Boolean {
        val code = event.keyCode
        if (!KeyEvent.isGamepadButton(code) && code !in DPAD) return false
        if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
            held = held.copy(keys = held.keys + code)
            lastKey = code
        } else if (event.action == KeyEvent.ACTION_UP) {
            held = held.copy(keys = held.keys - code)
        }
        return true
    }

    fun motion(event: MotionEvent): Boolean {
        if (event.source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK || event.action != MotionEvent.ACTION_MOVE) return false
        fun axis(code: Int) = event.getAxisValue(code)
        held = held.copy(
            hatX = axis(MotionEvent.AXIS_HAT_X), hatY = axis(MotionEvent.AXIS_HAT_Y),
            leftX = axis(MotionEvent.AXIS_X), leftY = axis(MotionEvent.AXIS_Y),
            rightX = axis(MotionEvent.AXIS_Z), rightY = axis(MotionEvent.AXIS_RZ),
            leftTrigger = maxOf(axis(MotionEvent.AXIS_LTRIGGER), axis(MotionEvent.AXIS_BRAKE)),
            rightTrigger = maxOf(axis(MotionEvent.AXIS_RTRIGGER), axis(MotionEvent.AXIS_GAS)),
        )
        return true
    }

    fun reset() { held = Held() }

    private companion object {
        val DPAD = setOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)
    }
}
