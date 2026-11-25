package io.github.sofianbll.oortnx.ui

import android.content.Context
import android.hardware.input.InputManager
import android.view.InputDevice
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R

private class Pad(val name: String, val vendor: Int, val product: Int)

/** The controllers Android sees, kept up to date as they come and go, and the last button pressed: a way to check a pad before a game. */
@Composable
fun ControllersScreen(state: AppState, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var pads by remember { mutableStateOf(connectedPads()) }
    DisposableEffect(context) {
        val manager = context.getSystemService(Context.INPUT_SERVICE) as InputManager
        val listener = object : InputManager.InputDeviceListener {
            override fun onInputDeviceAdded(deviceId: Int) { pads = connectedPads() }
            override fun onInputDeviceRemoved(deviceId: Int) { pads = connectedPads() }
            override fun onInputDeviceChanged(deviceId: Int) { pads = connectedPads() }
        }
        manager.registerInputDeviceListener(listener, null)
        onDispose { manager.unregisterInputDeviceListener(listener) }
    }
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.controllers_title), style = MaterialTheme.typography.headlineMedium)
        if (pads.isEmpty()) {
            Text(stringResource(R.string.controllers_none), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        for (pad in pads) {
            Column(Modifier.widthIn(max = 520.dp)) {
                Text(pad.name, style = MaterialTheme.typography.titleMedium)
                Text(
                    stringResource(R.string.controllers_ids, "%04x".format(pad.vendor), "%04x".format(pad.product)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        state.lastKey?.let {
            Text(stringResource(R.string.controllers_last, it), style = MaterialTheme.typography.titleSmall)
        }
        Text(
            stringResource(R.string.controllers_layout),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.widthIn(max = 520.dp),
        )
    }
}

private fun connectedPads(): List<Pad> = InputDevice.getDeviceIds().toList().mapNotNull { InputDevice.getDevice(it) }
    .filter { !it.isVirtual && (it.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD || it.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK) }
    .map { Pad(it.name, it.vendorId, it.productId) }
