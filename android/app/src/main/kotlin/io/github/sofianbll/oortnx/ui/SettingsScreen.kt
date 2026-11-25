package io.github.sofianbll.oortnx.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.github.sofianbll.oortnx.R

@Composable
fun SettingsScreen(state: AppState, modifier: Modifier = Modifier) {
    val prefs = state.prefs
    val calm = prefs.calm
    val version = LocalContext.current.let { it.packageManager.getPackageInfo(it.packageName, 0).versionName ?: "" }
    Column(
        modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(stringResource(R.string.settings_title), style = MaterialTheme.typography.headlineMedium)
        SettingRow(state, 0, R.string.settings_sound, R.string.settings_sound_note) {
            Switch(prefs.sound, { state.changeSetting(0) })
        }
        SettingRow(state, 1, R.string.settings_pack, null) {
            Text(prefs.pack.replaceFirstChar { it.uppercase() }, style = MaterialTheme.typography.titleSmall)
        }
        SettingRow(state, 2, R.string.settings_swap, R.string.settings_swap_note) {
            Switch(prefs.swapAB, { state.changeSetting(2) })
        }
        SettingRow(state, 3, R.string.settings_calm, R.string.settings_calm_note) {
            Switch(calm, { state.changeSetting(3) })
        }

        Text(stringResource(R.string.settings_about), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
        for (line in listOf(stringResource(R.string.settings_version, version), stringResource(R.string.settings_license), stringResource(R.string.settings_credits))) {
            Text(line, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.widthIn(max = 560.dp))
        }
    }
}

@Composable
private fun SettingRow(state: AppState, index: Int, title: Int, note: Int?, trailing: @Composable () -> Unit) {
    val shape = RoundedCornerShape(canvas(OortTokens.Radius.Card))
    FocusRing(state.padMode && state.settingsFocus == index, state.prefs.calm, shape, Modifier.widthIn(max = 560.dp).fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .clip(shape)
                .background(OortTokens.Palette.Glass.copy(alpha = 0.82f))
                .clickable { state.padMode = false; state.settingsFocus = index; state.changeSetting(index) }
                .heightIn(min = 56.dp)
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(Modifier.weight(1f)) {
                Text(stringResource(title), style = MaterialTheme.typography.titleMedium)
                if (note != null) {
                    Text(stringResource(note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            trailing()
        }
    }
}
