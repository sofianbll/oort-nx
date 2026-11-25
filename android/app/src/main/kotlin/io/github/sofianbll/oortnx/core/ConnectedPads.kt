package io.github.sofianbll.oortnx.core

import android.view.InputDevice

class ConnectedPad(val id: Int, val name: String, val vendor: Int, val product: Int) {
    val family: PadFamily get() = PadFamily.of(vendor, product, name)
}

val InputDevice.family: PadFamily get() = PadFamily.of(vendorId, productId, name)

/** The controllers Android sees now. */
fun connectedPads(): List<ConnectedPad> = InputDevice.getDeviceIds().toList().mapNotNull { InputDevice.getDevice(it) }
    .filter { !it.isVirtual && (it.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD || it.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK) }
    .map { ConnectedPad(it.id, it.name, it.vendorId, it.productId) }
