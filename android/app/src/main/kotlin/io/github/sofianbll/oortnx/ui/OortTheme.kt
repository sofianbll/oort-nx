package io.github.sofianbll.oortnx.ui

import androidx.compose.animation.core.AnimationSpec
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.ripple.RippleAlpha
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalRippleConfiguration
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RippleConfiguration
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Selene's canvas is 1920x1080 px, read from a sofa. A phone is read at arm's length: spacing and radii are
 * three quarters of a canvas unit in dp (a 16 px card radius is 12 dp). Text is not scaled: it takes Material's
 * type scale in sp, so it follows the system font size.
 */
fun canvas(units: Float): Dp = (units * 0.75f).dp

/** The sizes Android adds to the charter's tokens: its touch target and window class, and the app's strokes. */
object Metrics {
    /** Android's smallest touch target. */
    val Touch = 48.dp
    /** The height of the app's keys and fields. */
    val Key = 56.dp
    /** Material's first window class past a phone held upright. */
    val WideWindow = 600.dp
    /** Below this height the bottom bar leaves room for a key and enlarged controller hints. */
    val ShortPadKeyboardWindow = 360.dp
    /** The widest a list of lines grows. */
    val Measure = 780.dp
    val Ring = 2.dp
    val Line = 1.dp
    /** The room two lines of hints take on the first screen. */
    val Hints = 76.dp
    /** A pointer lights half of what a controller does: it points, it does not choose. */
    const val Hover = 0.5f
}

/** The charter's palette as Material roles. Dark only: Oort has one night. No dynamic color: the charter is the identity. */
private val OortColors = darkColorScheme(
    primary = OortTokens.Palette.Focus,
    onPrimary = OortTokens.Palette.OnFocus,
    primaryContainer = OortTokens.Primitive.OrbitHigh,
    onPrimaryContainer = OortTokens.Palette.Ink,
    secondary = OortTokens.Palette.Glyph,
    onSecondary = OortTokens.Palette.OnFocus,
    secondaryContainer = OortTokens.Primitive.OrbitHigh,
    onSecondaryContainer = OortTokens.Palette.Ink,
    tertiary = OortTokens.Palette.Success,
    onTertiary = OortTokens.Palette.OnFocus,
    background = OortTokens.Palette.Scrim,
    onBackground = OortTokens.Palette.Ink,
    surface = OortTokens.Palette.Glass,
    onSurface = OortTokens.Palette.Ink,
    surfaceVariant = OortTokens.Primitive.OrbitHigh,
    onSurfaceVariant = OortTokens.Palette.Light,
    surfaceContainer = OortTokens.Primitive.OrbitHigh,
    surfaceContainerHigh = OortTokens.Primitive.OrbitHigh,
    surfaceContainerHighest = OortTokens.Primitive.OrbitHigh,
    outline = OortTokens.Palette.Light,
    outlineVariant = OortTokens.Palette.Light.copy(alpha = OortTokens.Effect.SurfaceLine),
    error = OortTokens.Status.Danger,
    onError = OortTokens.Palette.OnFocus,
    scrim = OortTokens.Palette.Scrim,
)

private val OortShapes = Shapes(
    extraSmall = RoundedCornerShape(canvas(OortTokens.Radius.Row)),
    small = RoundedCornerShape(canvas(OortTokens.Radius.Content)),
    medium = RoundedCornerShape(canvas(OortTokens.Radius.Card)),
    large = RoundedCornerShape(canvas(OortTokens.Radius.Modal)),
    extraLarge = RoundedCornerShape(canvas(OortTokens.Radius.Dialog)),
)

@OptIn(ExperimentalMaterial3Api::class)
private val QuietRipple = RippleConfiguration(rippleAlpha = RippleAlpha(draggedAlpha = 0.16f, focusedAlpha = 0f, hoveredAlpha = 0.08f, pressedAlpha = 0.1f))

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OortTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = OortColors, shapes = OortShapes) {
        // The controller's ring is the app's own: Android's focus tint would light a second place.
        CompositionLocalProvider(LocalRippleConfiguration provides QuietRipple, content = content)
    }
}

/** A change that takes the token's duration, or happens at once when the player asked for calm. */
fun <T> motion(calm: Boolean, ms: Int): AnimationSpec<T> = if (calm) snap() else tween(ms)

/** [top] at [share] over [base]: the charter's panels are the page with a little ink. */
fun over(base: Color, top: Color, share: Float): Color = top.copy(alpha = share).compositeOver(base)

val Ink2: Color = OortTokens.Palette.Ink.copy(alpha = 0.72f)
val PanelLow: Color = over(OortTokens.Palette.Glass, OortTokens.Palette.Ink, OortTokens.Effect.SurfaceLow)
val PanelHigh: Color = over(OortTokens.Palette.Glass, OortTokens.Palette.Ink, OortTokens.Effect.SurfaceHigh)
val PanelRaised: Color = over(OortTokens.Palette.Glass, OortTokens.Palette.Ink, OortTokens.Effect.SurfaceRaised)
val Line: Color = OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.SurfaceLine)
val LineStrong: Color = OortTokens.Palette.Glyph.copy(alpha = OortTokens.Effect.SurfaceLineStrong)

fun Modifier.heading(): Modifier = semantics { heading() }
