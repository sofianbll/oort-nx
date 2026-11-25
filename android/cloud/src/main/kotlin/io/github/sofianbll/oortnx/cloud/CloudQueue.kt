package io.github.sofianbll.oortnx.cloud

import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfBuild
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfPlatform
import io.github.sofianbll.oortnx.shelf.jsonObject
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** One download the player asked for. */
internal data class CloudTask(
    val build: ShelfBuild,
    val state: State = State.WAITING,
    /** Why it stopped, or what it waits for: a [ShelfError] code. */
    val reason: String? = null,
    val needed: Long? = null,
    val received: Long = 0,
) {
    enum class State(val id: String) { WAITING("waiting"), RUNNING("running"), PAUSED("paused"), FAILED("failed"), READY("ready") }

    val id: String get() = build.titleID
}

/** The downloads in the order they were asked for, kept on the device so that nothing is lost when the process ends. One at a time. */
internal class CloudQueue(private val file: File) {
    var tasks: List<CloudTask> = load()
        private set

    operator fun get(id: String): CloudTask? = tasks.firstOrNull { it.id == id }
    val next: CloudTask? get() = if (tasks.any { it.state == CloudTask.State.RUNNING }) null else tasks.firstOrNull { it.state == CloudTask.State.WAITING }

    /** Asking again for a title replaces what was asked before. */
    fun add(build: ShelfBuild) = save(tasks.filter { it.id != build.titleID } + CloudTask(build))

    fun set(id: String, state: CloudTask.State, reason: ShelfError? = null) = save(tasks.map {
        if (it.id == id) it.copy(state = state, reason = reason?.code, needed = (reason as? ShelfError.NoSpace)?.needed?.takeIf { n -> n > 0 }) else it
    })

    /** In memory only: the files on the device say the rest. */
    fun progress(id: String, received: Long) { tasks = tasks.map { if (it.id == id) it.copy(received = received) else it } }

    fun remove(id: String) = save(tasks.filter { it.id != id })
    fun clear() { tasks = emptyList(); file.delete() }

    private fun save(next: List<CloudTask>) {
        tasks = next
        try {
            file.parentFile!!.mkdirs()
            val temporary = File(file.path + ".new")
            temporary.writeText(write(tasks.map { task ->
                mapOf("build" to fields(task.build), "state" to task.state.id, "reason" to task.reason, "needed" to task.needed)
            }))
            Files.move(temporary.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE)
        } catch (_: IOException) {
            // A full disk: the queue goes on in memory.
        }
    }

    /** A task that was running when the process ended waits its turn again. */
    private fun load(): List<CloudTask> {
        if (!file.exists()) return emptyList()
        val list = try { Json.read(file.readBytes()) as? List<*> } catch (_: IOException) { null } ?: return emptyList()
        return list.mapNotNull { item ->
            val map = item.jsonObject() ?: return@mapNotNull null
            val build = build(map["build"].jsonObject() ?: return@mapNotNull null) ?: return@mapNotNull null
            val state = CloudTask.State.entries.firstOrNull { it.id == map["state"] } ?: CloudTask.State.WAITING
            CloudTask(build, if (state == CloudTask.State.RUNNING) CloudTask.State.WAITING else state, map["reason"] as? String, map["needed"] as? Long)
        }.distinctBy { it.id }
    }

    companion object {
        private fun fields(b: ShelfBuild) = mapOf(
            "titleID" to b.titleID, "name" to b.name, "gameVersion" to b.gameVersion, "engineCommit" to b.engineCommit, "minimumSystem" to b.minimumSystem,
            "architecture" to b.architecture, "features" to b.features, "host" to b.host, "packagePath" to b.packagePath, "packageID" to b.packageID,
            "packageVersion" to b.packageVersion, "packageSigner" to b.packageSigner, "bytes" to b.bytes, "digest" to b.digest, "stamp" to b.stamp, "folder" to b.folder,
            "entries" to b.entries.map { mapOf("path" to it.path, "size" to it.size, "sha256" to it.sha256) },
        )

        private fun build(map: Map<String, Any?>): ShelfBuild? = try {
            ShelfBuild(
                map["titleID"] as String, map["name"] as String, ShelfPlatform.ANDROID, map["gameVersion"] as String, map["engineCommit"] as String,
                map["minimumSystem"] as String, map["architecture"] as String, (map["features"] as List<*>).map { it as String }, (map["host"] as Long).toInt(),
                map["packagePath"] as String, map["packageID"] as? String, map["packageVersion"] as? Long, map["packageSigner"] as? String, map["bytes"] as Long,
                (map["entries"] as List<*>).map { e -> e.jsonObject()!!.let { ShelfBuild.Entry(it["path"] as String, it["size"] as Long, it["sha256"] as String) } },
                map["digest"] as String, map["stamp"] as Long, map["folder"] as? String,
            )
        } catch (_: RuntimeException) {
            null
        }

        /** JSON of maps, lists, words, whole numbers, yes or no. */
        fun write(value: Any?): String = when (value) {
            null -> "null"
            is Boolean, is Int, is Long -> value.toString()
            is Map<*, *> -> value.entries.joinToString(",", "{", "}") { (k, v) -> write(k.toString()) + ":" + write(v) }
            is List<*> -> value.joinToString(",", "[", "]") { write(it) }
            else -> buildString {
                append('"')
                for (c in value.toString()) when {
                    c == '"' || c == '\\' -> append('\\').append(c)
                    c < ' ' -> append("\\u%04x".format(c.code))
                    else -> append(c)
                }
                append('"')
            }
        }
    }
}
