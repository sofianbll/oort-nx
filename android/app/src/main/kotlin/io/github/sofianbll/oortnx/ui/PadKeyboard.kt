package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import io.github.sofianbll.oortnx.R

/** The keys a controller types a search with; a finger can press them too. */
@Composable
fun PadKeyboard(state: AppState) {
    val space = stringResource(R.string.key_space)
    val erase = stringResource(R.string.key_erase)
    BoxWithConstraints(Modifier.fillMaxWidth().padding(bottom = canvas(OortTokens.Space.FieldInset))) {
        val columns = if (maxWidth >= Metrics.WideWindow) AppState.PAD_COLUMNS_WIDE else AppState.PAD_COLUMNS_COMPACT
        SideEffect { state.padKeyColumns = columns }
        // A key holds its letter at any text size.
        val density = LocalDensity.current
        val tall = (canvas(OortTokens.Space.Large) * density.fontScale.coerceAtLeast(1f) + canvas(OortTokens.Space.Section)).coerceAtLeast(Metrics.Touch)
        val keyHeight = with(density) { tall.roundToPx() }
        val rowHeight = keyHeight + with(density) { Metrics.Ring.roundToPx() }
        val scroll = rememberScrollState()
        val viewport = scroll.viewportSize
        LaunchedEffect(state.padMode, state.padKey, columns, rowHeight, viewport) {
            if (!state.padMode || viewport == 0) return@LaunchedEffect
            val top = state.padKey / columns * rowHeight
            val bottom = top + keyHeight
            val firstVisible = (bottom - viewport).coerceAtMost(top)
            scroll.scrollTo(scroll.value.coerceIn(firstVisible, top))
        }
        Column(Modifier.widthIn(max = Metrics.Measure).verticalScroll(scroll), verticalArrangement = Arrangement.spacedBy(Metrics.Ring)) {
            AppState.PAD_KEYS.chunked(columns).forEachIndexed { row, keys ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Metrics.Ring)) {
                    keys.forEachIndexed { column, key ->
                        val index = row * columns + column
                        val lit = state.padMode && state.padKey == index
                        val shape = RoundedCornerShape(canvas(OortTokens.Radius.Row))
                        val said = when (key) { AppState.KEY_SPACE -> space; AppState.KEY_ERASE -> erase; else -> null }
                        Box(
                            Modifier.weight(1f).height(tall).border(Metrics.Ring, if (lit) OortTokens.Palette.Focus else Color.Transparent, shape).padding(Metrics.Ring)
                                .clip(shape).background(if (lit) PanelHigh else PanelRaised).clickable(role = Role.Button) { state.pressKey(index) }
                                .semantics { said?.let { contentDescription = it } },
                            contentAlignment = Alignment.Center,
                        ) { Text(key, color = OortTokens.Palette.Ink, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1) }
                    }
                    repeat(columns - keys.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}
