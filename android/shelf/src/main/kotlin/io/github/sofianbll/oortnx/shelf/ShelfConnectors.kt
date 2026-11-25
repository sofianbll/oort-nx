package io.github.sofianbll.oortnx.shelf

/**
 * A way to read the library that the player may turn on. The core knows none by name: an app lists the ones it was built with, so
 * leaving one out means leaving out one line and its module.
 */
class ShelfConnector(
    val id: String,
    /** Every host it may speak to, for the screen that asks the player and for the test that checks it. */
    val hosts: List<String>,
    val permissions: Set<Permission>,
    internal val open: () -> ShelfSource,
    /** Erases what the connector kept on the device (its credential). */
    internal val forget: () -> Unit,
) {
    enum class Permission(val id: String) { NETWORK("network"), READ_LIBRARY("readLibrary"), STORE_BUILDS("storeBuilds") }
}

/** Where the player's choices are kept. */
interface ShelfChoices {
    fun permissions(connector: String): Set<String>?
    fun set(permissions: Set<String>?, connector: String)
}

/** Every connector is off until the player turns it on, with the permissions that were shown. Nothing is opened before that. */
class ShelfConnectors(val all: List<ShelfConnector>, private val choices: ShelfChoices) {
    /** An app update that asks for more turns the connector off again until the player agrees. */
    fun isOn(id: String): Boolean {
        val connector = connector(id) ?: return false
        val granted = choices.permissions(id) ?: return false
        return granted.containsAll(connector.permissions.map { it.id })
    }

    fun turnOn(id: String, granting: Set<ShelfConnector.Permission>) {
        val connector = connector(id)
        if (connector == null || !granting.containsAll(connector.permissions)) fail(ShelfError.SourceOff)
        choices.set(granting.map { it.id }.toSet(), id)
    }

    /** Off first, then forgotten: a failure to erase never leaves it on. */
    fun turnOff(id: String) {
        choices.set(null, id)
        connector(id)?.forget?.invoke()
    }

    fun source(id: String): ShelfSource {
        val connector = connector(id)
        if (connector == null || !isOn(id)) fail(ShelfError.SourceOff)
        return connector.open()
    }

    private fun connector(id: String) = all.firstOrNull { it.id == id }
}
