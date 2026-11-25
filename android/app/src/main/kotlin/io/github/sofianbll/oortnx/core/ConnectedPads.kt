package io.github.sofianbll.oortnx.core

import android.view.InputDevice
import android.view.KeyEvent

class ConnectedPad(val id: Int, val name: String, val vendor: Int, val product: Int) {
    val family: PadFamily get() = PadFamily.of(vendor, product, name)
}

/** True for a key typed on a keyboard with letters, not pressed on a pad or a remote. */
val KeyEvent.fromKeyboard: Boolean
    get() = !isFromSource(InputDevice.SOURCE_GAMEPAD) && !isFromSource(InputDevice.SOURCE_JOYSTICK) &&
        device?.keyboardType == InputDevice.KEYBOARD_TYPE_ALPHABETIC

val InputDevice.family: PadFamily get() = PadFamily.of(vendorId, productId, name)

/** The controllers Android sees now. */
fun connectedPads(): List<ConnectedPad> = InputDevice.getDeviceIds().toList().mapNotNull { InputDevice.getDevice(it) }
    .filter { !it.isVirtual && (it.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD || it.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK) }
    .map { ConnectedPad(it.id, it.name, it.vendorId, it.productId) }
