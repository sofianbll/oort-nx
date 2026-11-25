package io.github.sofianbll.oortnx.drive

import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfChoices
import io.github.sofianbll.oortnx.shelf.jsonObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import java.util.concurrent.TimeUnit

/** Tests/PhoneLibrary/fake_drive.py, one process per test, on 127.0.0.1. */
class FakeDrive(vector: File) : AutoCloseable {
    private val process = ProcessBuilder("python3", "-I", "-B", File(folder, "fake_drive.py").path, vector.path)
        .redirectError(ProcessBuilder.Redirect.INHERIT).start()
    private val port = process.inputStream.bufferedReader().readLine().trim().toInt()

    internal fun endpoints(up: Boolean = true): DriveEndpoints {
        val base = "http://127.0.0.1:${if (up) port else 1}"
        return DriveEndpoints("$base/auth", "$base/token", "$base/drive/v3/files")
    }

    class Call(val call: String, val node: String?, val first: Long?, val last: Long?, val fields: List<*>?)

    /** What was asked since the last time. */
    fun log(): List<Call> = (Json.read(URI("http://127.0.0.1:$port/__log").toURL().readBytes()) as List<*>).map {
        val map = it.jsonObject()!!
        Call(map["call"] as String, map["node"] as? String, map["first"] as? Long, map["last"] as? Long, map["fields"] as? List<*>)
    }

    fun remember(code: String, challenge: String) {
        val connection = URI("http://127.0.0.1:$port/__code").toURL().openConnection() as HttpURLConnection
        connection.doOutput = true
        connection.outputStream.use { it.write("code=$code&challenge=$challenge".toByteArray()) }
        check(connection.responseCode == 200)
    }

    override fun close() {
        process.outputStream.close()
        if (!process.waitFor(5, TimeUnit.SECONDS)) process.destroyForcibly()
    }

    companion object {
        val folder = File(System.getProperty("oort.cases")!!)
    }
}

class MemoryVault(private var secret: DriveSecret?) : DriveVault {
    override fun read(): DriveSecret? = secret
    override fun write(secret: DriveSecret) { this.secret = secret }
    override fun erase() { secret = null }
}

class MemoryChoices : ShelfChoices {
    private val values = HashMap<String, Set<String>>()
    override fun permissions(connector: String): Set<String>? = values[connector]
    override fun set(permissions: Set<String>?, connector: String) {
        if (permissions == null) values.remove(connector) else values[connector] = permissions
    }
}
