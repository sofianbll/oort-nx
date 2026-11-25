package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import io.github.sofianbll.oortnx.R

/**
 * A game's options, over the page: from the foot of a narrow window, in the middle of a wide one. Drawn in the app's own
 * window, not in a dialog's, so the controller keeps reaching it as it reaches every list.
 */
@Composable
fun GameMenu(state: AppState) {
    val game = state.menuGame ?: return
    val close = stringResource(R.string.close)
    val options = stringResource(R.string.options)
    BoxWithConstraints(Modifier.fillMaxSize()) {
        // A touch beside the panel closes it.
        Box(Modifier.fillMaxSize().background(OortTokens.Palette.Scrim.copy(alpha = OortTokens.Effect.MenuVeil))
            .clickable(interactionSource = null, indication = null) { state.onBack() }.semantics { contentDescription = close })
        val wide = maxWidth >= Metrics.WideWindow
        val shape = RoundedCornerShape(canvas(OortTokens.Radius.Dialog))
        Column(
            Modifier.align(if (wide) Alignment.Center else Alignment.BottomCenter).safeDrawingPadding().padding(canvas(OortTokens.Space.Medium)).widthIn(max = canvas(OortTokens.Space.SidePanel)).fillMaxWidth()
                .clip(shape).background(OortTokens.Palette.Glass).border(Metrics.Line, LineStrong, shape)
                .pointerInput(Unit) { } // a touch on the panel is not a touch beside it
                .semantics { paneTitle = options }.padding(horizontal = canvas(OortTokens.Space.FieldInset), vertical = canvas(OortTokens.Space.Medium)),
            verticalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.FieldInset)),
        ) {
            Text(game.title, Modifier.padding(horizontal = canvas(OortTokens.Space.Medium)).heading(), color = OortTokens.Palette.Ink, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())) { OortList(state, state.sections()) }
            Hints(state, listOf(HintKey.Confirm to R.string.select, HintKey.Back to R.string.close), Modifier.padding(horizontal = canvas(OortTokens.Space.Medium)))
        }
    }
}
