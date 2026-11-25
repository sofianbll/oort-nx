package io.github.sofianbll.oortnx.cloud

import android.content.Context
import android.content.pm.PackageManager

/** Only Oort NX, signed with the same key, may ask anything of this app. */
internal object CloudGuard {
    const val OORT = "io.github.sofianbll.oortnx.alpha"

    fun allows(context: Context, caller: String?): Boolean = isOort(caller) &&
        context.packageManager.checkSignatures(context.packageName, OORT) == PackageManager.SIGNATURE_MATCH

    /** Apart from Android, for a test. */
    fun isOort(caller: String?): Boolean = caller == OORT
}
