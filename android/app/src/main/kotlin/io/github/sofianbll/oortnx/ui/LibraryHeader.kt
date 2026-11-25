package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import io.github.sofianbll.oortnx.R

/** The library's name, its search and sort keys, and its two tabs: every game, or the favourites. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LibraryHeader(state: AppState) {
    fun lit(key: LibraryKey) = state.padMode && state.libraryKey == key
    // While a controller types, the field and the keys take the title's and the tabs' room: what is found stays in view.
    if (!state.padKeyboard) PageTitle(stringResource(R.string.nav_library), null) {
        IconKey(Glyph.Search, stringResource(R.string.search), lit(LibraryKey.Search)) { state.search() }
        SortKey(state, lit(LibraryKey.Sort))
    }
    if (state.searching) SearchField(state)
    if (!state.padKeyboard) FlowRow(Modifier.fillMaxWidth().padding(bottom = canvas(OortTokens.Space.Medium)), horizontalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.FieldInset)), verticalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.FieldInset))) {
        Tab(stringResource(R.string.tab_all), !state.onlyFavorites, lit(LibraryKey.All)) { state.filter(false) }
        Tab(stringResource(R.string.tab_favorites), state.onlyFavorites, lit(LibraryKey.Favorites)) { state.filter(true) }
    }
}

@Composable
private fun Tab(label: String, on: Boolean, focused: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.border(Metrics.Ring, if (focused) OortTokens.Palette.Focus else Color.Transparent, CircleShape).padding(canvas(OortTokens.Space.Hairline)).clip(CircleShape)
            .background(if (on) OortTokens.Palette.Focus else PanelRaised).selectable(on, role = Role.Tab, onClick = onClick)
            .defaultMinSize(minHeight = Metrics.Touch).padding(horizontal = canvas(OortTokens.Space.Large), vertical = canvas(OortTokens.Space.FieldInset)),
        contentAlignment = Alignment.Center,
    ) { Text(label, color = if (on) OortTokens.Palette.OnFocus else OortTokens.Palette.Ink, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold) }
}

/** The system's own keyboard types here, under a finger or a controller. */
@Composable
private fun SearchField(state: AppState) {
    val focus = remember { FocusRequester() }
    val manager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    // Asked for once per request: coming back to the page does not bring the keyboard up again.
    LaunchedEffect(state.fieldAsked) {
        if (state.takeFieldRequest()) { focus.requestFocus(); keyboard?.show() }
    }
    var left by remember { mutableStateOf(state.fieldLeft) }
    LaunchedEffect(state.fieldLeft) {
        if (state.fieldLeft != left) { keyboard?.hide(); manager.clearFocus() }
        left = state.fieldLeft
    }
    val hint = stringResource(R.string.search_field)
    val shape = CircleShape
    Row(
        Modifier.padding(top = canvas(if (state.padKeyboard) OortTokens.Space.FieldInset else 0f)).fillMaxWidth().padding(bottom = canvas(OortTokens.Space.Line)).widthIn(max = Metrics.Measure).clip(shape).background(PanelRaised)
            .border(BorderStroke(Metrics.Line, if (state.typing) OortTokens.Palette.Focus else LineStrong), shape).padding(start = canvas(OortTokens.Space.RowLeading), end = canvas(OortTokens.Space.Hairline)),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(canvas(OortTokens.Space.FieldInset)),
    ) {
        BasicTextField(
            state.query, { state.type(it) },
            Modifier.weight(1f).focusRequester(focus).onFocusChanged { state.typing = it.isFocused; if (it.isFocused) state.padKeyboard = false }
                .semantics { contentDescription = hint },
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = OortTokens.Palette.Ink),
            cursorBrush = SolidColor(OortTokens.Palette.Focus),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { state.leaveField() }),
            decorationBox = { field ->
                Box(Modifier.defaultMinSize(minHeight = Metrics.Key), contentAlignment = Alignment.CenterStart) {
                    if (state.query.isEmpty()) Text(hint, style = MaterialTheme.typography.bodyLarge, color = Ink2)
                    field()
                }
            },
        )
        IconKey(Glyph.Close, stringResource(R.string.close)) { state.onBack() }
    }
}

@Composable
private fun SortKey(state: AppState, focused: Boolean) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconKey(Glyph.Sort, stringResource(R.string.sort), focused) { open = true }
        DropdownMenu(open, { open = false }, containerColor = PanelRaised, border = BorderStroke(Metrics.Line, LineStrong)) {
            for ((byName, label) in listOf(false to R.string.sort_last, true to R.string.sort_name)) {
                DropdownMenuItem(
                    text = { Text(stringResource(label), style = MaterialTheme.typography.bodyLarge) },
                    onClick = { open = false; state.sort(byName) },
                    trailingIcon = { if (state.prefs.byName == byName) OortGlyph(Glyph.Check) },
                    modifier = Modifier.semantics { selected = state.prefs.byName == byName },
                )
            }
        }
    }
}
