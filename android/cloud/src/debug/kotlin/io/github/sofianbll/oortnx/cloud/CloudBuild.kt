package io.github.sofianbll.oortnx.cloud

import io.github.sofianbll.oortnx.drive.DriveEndpoints

/** What this build speaks to: Google, and nothing else. */
internal object CloudBuild {
    val endpoints: DriveEndpoints get() = DriveEndpoints.google
    const val CHUNK = 8L shl 20
    val free: Long? get() = null
    val metered: Boolean get() = false
}
