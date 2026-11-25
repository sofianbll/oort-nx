package io.github.sofianbll.oortnx

import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.hardware.input.InputManager
import android.os.Bundle
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.ViewGroup
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
import io.github.sofianbll.oortnx.core.fromKeyboard
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
        savedInstanceState?.let { state.restore(it) }
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
        // After a touch Android spends the first arrow or Tab on giving the focus to a view: give it one beforehand.
        findViewById<ViewGroup>(android.R.id.content).getChildAt(0)?.let { it.isFocusableInTouchMode = true; it.requestFocus() }
        // Boots with the Sun's sound, once per start (the same event as the Mac's launch); not when Android rebuilds the page.
        if (savedInstanceState == null) sound.play(SoundEvent.Boot)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        state.save(outState)
    }

    private val padListener = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) { readPads() }
        override fun onInputDeviceRemoved(deviceId: Int) {
            readPads(); router.reset(); state.pad.reset()
            // The last controller left: its ring and its hints leave with it. A keyboard keeps its own.
            if (state.pads.isEmpty() && !state.keyboard) state.padMode = false
        }
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
        // A keyboard's keys are not a pad's: its arrows would light the dots of a controller nobody holds.
        val typed = event.fromKeyboard
        val ours = !typed && state.pad.key(event)
        if (ours) follow(event.device)
        if (ours && testing) { router.reset(); state.padMode = true; return true }
        // In the search field the letters and the arrows are the text's; Escape closes it and Down goes to what it found.
        if (state.typing) {
            if (event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
                if (event.action == KeyEvent.ACTION_DOWN) { state.keyboard = typed; state.padMode = true; state.leaveField() }
                return true
            }
            if (typed && !event.isCtrlPressed && event.keyCode != KeyEvent.KEYCODE_ESCAPE) return super.dispatchKeyEvent(event)
        }
        if (!router.key(event)) return super.dispatchKeyEvent(event)
        state.keyboard = typed // after the router: what it did is shown with the keys that did it
        return true
    }

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
        val ours = state.pad.motion(event)
        if (ours) { follow(event.device); if (state.pad.held.active) state.keyboard = false }
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
