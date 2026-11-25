package io.github.sofianbll.oortnx.cloud

import io.github.sofianbll.oortnx.drive.DriveEndpoints

/** The emulator's checks only: a stand-in for Google on the machine that runs them, through `adb reverse`. Never published. */
internal object CloudBuild {
    private const val BASE = "http://127.0.0.1:8799"
    val endpoints: DriveEndpoints get() = DriveEndpoints("$BASE/auth", "$BASE/token", "$BASE/drive/v3/files")
    const val CHUNK = 1L shl 20
    val free: Long? get() = property("debug.oort.free").toLongOrNull()
    val metered: Boolean get() = property("debug.oort.metered") == "1"

    private fun property(name: String): String = try {
        ProcessBuilder("getprop", name).start().inputStream.bufferedReader().readText().trim()
    } catch (_: java.io.IOException) {
        ""
    }
}
