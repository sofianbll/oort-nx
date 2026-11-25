package io.github.sofianbll.oortnx

import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Bundle
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
import io.github.sofianbll.oortnx.ui.AppState
import io.github.sofianbll.oortnx.ui.OortApp
import io.github.sofianbll.oortnx.ui.OortTheme
import io.github.sofianbll.oortnx.ui.Section
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
        state = AppState(applicationContext, prefs, sound, demo = debuggable && intent.getBooleanExtra("demo", false))
        router = InputRouter(
            swapAB = { prefs.swapAB },
            sink = { state.onNav(it) },
            onKey = { state.lastKey = KeyEvent.keyCodeToString(it).removePrefix("KEYCODE_") },
        )
        setContent {
            OortTheme {
                LaunchedEffect(Unit) {
                    while (true) { delay(20); router.poll() }
                }
                BackHandler(enabled = state.detail != null || state.section != Section.Library) { state.onBack() }
                OortApp(state)
            }
        }
        // Boots with the Sun's sound, once per start (the same event as the Mac's launch).
        sound.play(SoundEvent.Boot)
    }

    override fun onResume() {
        super.onResume()
        state.rescan() // a game may have been installed or removed while another app was in front
    }

    override fun onPause() {
        router.reset()
        super.onPause()
    }

    override fun onDestroy() {
        sound.release()
        super.onDestroy()
    }

    // A controller's buttons reach the activity here before any view: the pad drives the whole launcher.
    override fun dispatchKeyEvent(event: KeyEvent): Boolean = router.key(event) || super.dispatchKeyEvent(event)

    override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean = router.motion(event) || super.dispatchGenericMotionEvent(event)
}
