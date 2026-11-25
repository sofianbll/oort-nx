package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints

/** One card under the other; `level` makes them all as tall as the tallest. */
@Composable
fun CreditCards(level: Boolean, content: @Composable () -> Unit) {
    val gap = with(LocalDensity.current) { canvas(OortTokens.Space.Medium).roundToPx() }
    Layout(content, Modifier.fillMaxWidth()) { cards, constraints ->
        val width = constraints.maxWidth
        val height = if (level) cards.maxOfOrNull { it.maxIntrinsicHeight(width) } ?: 0 else 0
        val placed = cards.map { it.measure(Constraints(minWidth = width, maxWidth = width, minHeight = height)) }
        layout(width, placed.sumOf { it.height } + gap * maxOf(placed.size - 1, 0)) {
            var y = 0
            for (card in placed) { card.place(0, y); y += card.height + gap }
        }
    }
}

/** A project Oort NX owes something to, as on every system: its mark, its name, who makes it under which licence, what it does here. */
@Composable
fun RowScope.CreditCard(name: Label, face: CreditFace) {
    val shape = RoundedCornerShape(canvas(OortTokens.Radius.Content))
    val side = canvas(OortTokens.Space.Group)
    Box(
        Modifier.align(Alignment.Top).size(side).then(if (face.picture == null) Modifier.background(PanelRaised, shape) else Modifier),
        contentAlignment = Alignment.Center,
    ) {
        if (face.picture != null) Image(painterResource(face.picture), null, Modifier.size(side))
        else OortGlyph(face.glyph, tint = OortTokens.Palette.Ink, modifier = Modifier.size(canvas(OortTokens.Space.Large)))
    }
    Column(Modifier.align(Alignment.Top).weight(1f), verticalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.Seam))) {
        // The arrow stands beside the name; the rest has the whole width.
        Row(horizontalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.Compact)), verticalAlignment = Alignment.CenterVertically) {
            Text(name.text(), Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = OortTokens.Palette.Ink)
            OortGlyph(Glyph.Out, tint = Ink2, modifier = Modifier.size(canvas(OortTokens.Space.Control)))
        }
        Text(face.byline.text(), style = MaterialTheme.typography.bodyMedium, color = Ink2)
        Text(face.role.text(), Modifier.padding(top = canvas(OortTokens.Space.Hairline)), style = MaterialTheme.typography.bodyMedium, color = OortTokens.Palette.Ink)
    }
}
