package io.github.sofianbll.oortnx.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/**
 * The focus the controller moves: a full outline in the charter's white, not a bar down one side. It is drawn
 * only while the player is using a pad or a keyboard ([focused] is false for touch), so a phone in the hand shows no stray ring.
 */
@Composable
fun FocusRing(focused: Boolean, calm: Boolean, shape: Shape, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val ring by animateColorAsState(
        targetValue = if (focused) OortTokens.Palette.Focus else Color.Transparent,
        animationSpec = motion(calm, if (focused) OortTokens.Motion.FocusInMs else OortTokens.Motion.FocusOutMs),
        label = "focus ring",
    )
    Box(modifier.border(2.dp, ring, shape)) { content() }
}
