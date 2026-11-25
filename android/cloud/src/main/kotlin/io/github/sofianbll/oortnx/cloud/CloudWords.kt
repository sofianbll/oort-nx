package io.github.sofianbll.oortnx.cloud

import android.content.Context
import android.content.res.Configuration
import android.os.LocaleList

/** The language Oort NX speaks, which the player may have chosen for it alone. */
internal object CloudWords {
    fun save(context: Context, tag: String?) {
        val prefs = context.getSharedPreferences("words", Context.MODE_PRIVATE)
        if (tag != null && tag != prefs.getString("language", null)) prefs.edit().putString("language", tag).apply()
    }

    fun of(context: Context): Context {
        val tag = context.getSharedPreferences("words", Context.MODE_PRIVATE).getString("language", null) ?: return context
        return context.createConfigurationContext(Configuration(context.resources.configuration).apply { setLocales(LocaleList.forLanguageTags(tag)) })
    }
}
