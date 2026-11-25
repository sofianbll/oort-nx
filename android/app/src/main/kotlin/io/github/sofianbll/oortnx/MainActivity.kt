package io.github.sofianbll.oortnx

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.hardware.input.InputManager
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import io.github.sofianbll.oortnx.core.InputRouter
import io.github.sofianbll.oortnx.core.Prefs
import io.github.sofianbll.oortnx.core.SoundEvent
import io.github.sofianbll.oortnx.core.SoundPlayer
import io.github.sofianbll.oortnx.core.connectedPads
import io.github.sofianbll.oortnx.core.family
import io.github.sofianbll.oortnx.ui.AppState
import io.github.sofianbll.oortnx.ui.OortApp
import io.github.sofianbll.oortnx.ui.OortTheme
import io.github.sofianbll.oortnx.ui.Route
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private lateinit var state: AppState
    private lateinit var sound: SoundPlayer
    private lateinit var router: InputRouter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT), navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT))
        val prefs = Prefs(applicationContext)
        sound = SoundPlayer(prefs)
        val debuggable = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
        state = AppState(applicationContext, prefs, sound, demo = debuggable && intent.getBooleanExtra("demo", false),
            versionName = packageManager.getPackageInfo(packageName, 0).versionName ?: "")
        router = InputRouter(
            swapAB = { prefs.swapAB },
            sink = { state.onNav(it) },
        )
        setContent {
            OortTheme {
                LaunchedEffect(Unit) {
                    while (true) { delay(20); router.poll() }
                }
                BackHandler(enabled = state.canGoBack) { state.onBack() }
                OortApp(state)
            }
        }
        // Boots with the Sun's sound, once per start (the same event as the Mac's launch).
        sound.play(SoundEvent.Boot)
    }

    private val padListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) { readPads() }
        override fun onInputDeviceRemoved(deviceId: Int) { readPads(); router.reset(); state.pad.reset() }
        override fun onInputDeviceChanged(deviceId: Int) { readPads() }
    }

    override fun onResume() {
        super.onResume()
        state.prefs.refresh()
        readPads()
        (getSystemService(Context.INPUT_SERVICE) as InputManager).registerInputDeviceListener(padListener, null)
        state.rescan() // a game may have been installed or removed while another app was in front
    }

    override fun onPause() {
        (getSystemService(Context.INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(padListener)
        router.reset()
        state.pad.reset()
        super.onPause()
    }

    override fun onDestroy() {
        sound.release()
        super.onDestroy()
    }

    // A controller's buttons reach the activity here before any view: the pad drives the whole launcher.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val ours = state.pad.key(event)
        if (ours) follow(event.device)
        if (ours && testing) { router.reset(); state.padMode = true; return true }
        return router.key(event) || super.dispatchKeyEvent(event)
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val ours = state.pad.motion(event)
        if (ours) follow(event.device)
        if (ours && testing) { router.reset(); state.padMode = true; return true }
        return router.motion(event) || super.dispatchGenericMotionEvent(event)
    }

    /** The hints take the marks of the controller that was just used. */
    private fun follow(device: InputDevice?) { device?.let { state.family = it.family } }

    private fun readPads() {
        state.pads = connectedPads()
        // Before any button, the only controller there is gives its marks.
        state.pads.singleOrNull()?.let { state.family = it.family }
    }

    /** The screen where every button is tried takes them all. */
    private val testing: Boolean get() = state.route == Route.PadTest

    // A finger on the screen: the controller's ring and hints leave.
    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_DOWN) state.padMode = false
        return super.dispatchTouchEvent(event)
    }
}
