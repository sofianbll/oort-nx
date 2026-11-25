package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R

/** A page of lines: settings, controllers, credits. */
@Composable
fun ListScreen(state: AppState, title: String, onBack: (() -> Unit)?) {
    val sections = state.sections()
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        PageTitle(title, onBack)
        val scroll = rememberScrollState()
        val first = state.padMode && sections.flatMap { it.rows }.firstOrNull { it.kind != Kind.Info }?.id == state.focusedRow()
        LaunchedEffect(first) { if (first) scroll.animateScrollTo(0) }
        Column(Modifier.weight(1f).verticalScroll(scroll).padding(top = 8.dp, bottom = 32.dp)) {
            OortList(state, sections, Modifier.widthIn(max = 780.dp))
        }
        if (sections.any { s -> s.rows.any { it.kind != Kind.Info } }) PageHints(state)
    }
}

/** Which games Oort finds, in words. */
@Composable
fun WhichGamesScreen(state: AppState) {
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        PageTitle(stringResource(R.string.settings_which), { state.onBack() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            for (text in listOf(R.string.empty_body, R.string.which_limits)) {
                Text(stringResource(text), Modifier.widthIn(max = 620.dp), style = MaterialTheme.typography.bodyLarge, color = Ink2)
            }
        }
    }
}

/** A licence as it is written, from the app's own files. */
@Composable
fun LicenceScreen(state: AppState, licence: LicenceText) {
    val context = LocalContext.current
    val paragraphs = remember(licence) {
        context.assets.open("licences/${licence.file}").bufferedReader().use { it.readText() }.trim().split(Regex("\n\\s*\n"))
    }
    val list = rememberLazyListState()
    var seen by remember { mutableIntStateOf(state.textSteps) }
    val step = with(LocalDensity.current) { 220.dp.toPx() }
    LaunchedEffect(state.textSteps) {
        val by = state.textSteps - seen
        seen = state.textSteps
        if (by != 0) list.animateScrollBy(by * step)
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        PageTitle(licence.title, { state.onBack() })
        SelectionContainer(Modifier.weight(1f)) {
            LazyColumn(state = list, verticalArrangement = Arrangement.spacedBy(14.dp), contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp)) {
                items(paragraphs) { Text(it, Modifier.widthIn(max = 680.dp), style = MaterialTheme.typography.bodyMedium, color = Ink2) }
            }
        }
    }
}
