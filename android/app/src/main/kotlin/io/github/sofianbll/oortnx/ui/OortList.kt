package io.github.sofianbll.oortnx.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp

/** The app's list: sections of lines on Oort's panels. */
@Composable
fun OortList(state: AppState, sections: List<RowSection>, modifier: Modifier = Modifier) {
    val focus = if (state.padMode) state.focusedRow() else null // a page under the menu has none of its ids
    Column(modifier, verticalArrangement = Arrangement.spacedBy(28.dp)) {
        for (section in sections) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                section.title?.let { Text(it.text(), Modifier.padding(horizontal = 20.dp).heading(), style = MaterialTheme.typography.titleSmall, color = Ink2, fontWeight = FontWeight.SemiBold) }
                Column(Modifier.fillMaxWidth().oortPanel(RoundedCornerShape(canvas(OortTokens.Radius.Dialog)))) {
                    section.rows.forEachIndexed { index, row ->
                        if (index > 0) Spacer(Modifier.padding(start = if (row.glyph != null) 60.dp else 20.dp, end = 20.dp).fillMaxWidth().height(1.dp).background(Line))
                        Line(state, row, focused = row.id == focus)
                    }
                }
                section.footer?.let { Text(it.text(), Modifier.padding(horizontal = 20.dp), style = MaterialTheme.typography.bodyMedium, color = Ink2) }
            }
        }
    }
}

@Composable
private fun Line(state: AppState, row: RowItem, focused: Boolean) {
    val calm = state.prefs.calm
    val into = remember { BringIntoViewRequester() }
    var size by remember { mutableStateOf(IntSize.Zero) }
    val room = with(LocalDensity.current) { 56.dp.toPx() }
    // With room around it, so the line is not left under the fade at the foot of a page.
    LaunchedEffect(focused) { if (focused) into.bringIntoView(Rect(0f, -room, size.width.toFloat(), size.height + room)) }
    val light by animateFloatAsState(if (focused) 1f else 0f, motion(calm, OortTokens.Motion.FocusInMs), label = "line")
    val press = { state.padMode = false; state.press(row.id) }
    val act = when (val kind = row.kind) {
        Kind.Info -> Modifier.semantics(mergeDescendants = true) { }
        is Kind.Toggle -> Modifier.toggleable(kind.on, role = Role.Switch) { press() }
        is Kind.Pick -> Modifier.selectable(kind.on, role = Role.RadioButton) { press() }
        else -> Modifier.clickable(role = Role.Button) { press() }
    }
    val ring = RoundedCornerShape(canvas(OortTokens.Radius.Dialog) - 4.dp)
    Row(
        Modifier
            .bringIntoViewRequester(into)
            .onSizeChanged { size = it }
            .fillMaxWidth()
            .drawBehind {
                if (light > 0f) {
                    drawRect(OortTokens.Palette.Glyph.copy(alpha = 0.08f * light))
                    halftone(light, OortTokens.Palette.Glyph.copy(alpha = 0.10f))
                }
            }
            .then(act)
            .padding(4.dp)
            .border(2.dp, OortTokens.Palette.Focus.copy(alpha = light), ring)
            .heightIn(min = 60.dp)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        val tint = if (row.danger) OortTokens.Status.Danger else OortTokens.Palette.Glyph
        row.glyph?.let { OortGlyph(it, tint = tint, modifier = Modifier.size(26.dp).padding(1.dp)) }
        // Large text: the value goes under its title rather than squeezing it.
        val big = LocalDensity.current.fontScale >= 1.5f
        Column(Modifier.weight(1.1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(row.title.text(), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = if (row.danger) OortTokens.Status.Danger else OortTokens.Palette.Ink)
            row.note?.let { Text(it.text(), style = MaterialTheme.typography.bodyMedium, color = Ink2) }
            if (big) row.value?.let { Text(it.text(), style = MaterialTheme.typography.bodyLarge, color = Ink2) }
        }
        if (!big) row.value?.let { Text(it.text(), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, color = Ink2, textAlign = TextAlign.End) }
        when (val kind = row.kind) {
            is Kind.Open -> OortGlyph(Glyph.Forward, tint = Ink2, modifier = Modifier.size(18.dp))
            is Kind.Press -> Unit
            is Kind.Toggle -> DotSwitch(kind.on, calm)
            is Kind.Pick -> Box(Modifier.size(24.dp)) { if (kind.on) OortGlyph(Glyph.Check, tint = OortTokens.Palette.Focus) }
            Kind.Info -> Unit
        }
    }
}

/** The switch of the Mac app: a track of dots that fills when it is on. The whole line is the target. */
@Composable
private fun DotSwitch(on: Boolean, calm: Boolean) {
    val x by animateFloatAsState(if (on) 1f else 0f, motion(calm, OortTokens.Motion.MoveMs), label = "switch")
    Box(Modifier.size(56.dp, 32.dp).clip(CircleShape).background(PanelLow).border(1.dp, if (on) OortTokens.Palette.Focus.copy(alpha = 0.55f) else LineStrong, CircleShape)) {
        Canvas(Modifier.size(56.dp, 32.dp)) {
            drawRect(OortTokens.Palette.Glyph.copy(alpha = 0.28f * x))
            halftone(x, OortTokens.Palette.Focus.copy(alpha = 0.9f))
            val r = 12.5.dp.toPx()
            val inset = 3.5.dp.toPx() + r
            val centre = Offset(inset + (size.width - 2 * inset) * x, size.height / 2)
            drawCircle(OortTokens.Palette.Scrim.copy(alpha = 0.4f), r + 1.5.dp.toPx(), centre)
            drawCircle(if (on) OortTokens.Palette.Focus else Ink2, r, centre)
        }
    }
}
