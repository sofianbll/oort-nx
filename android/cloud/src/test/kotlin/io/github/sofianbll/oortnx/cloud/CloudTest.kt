package io.github.sofianbll.oortnx.cloud

import com.google.zxing.BarcodeFormat
import com.google.zxing.qrcode.QRCodeWriter
import io.github.sofianbll.oortnx.shelf.Json
import io.github.sofianbll.oortnx.shelf.ShelfBuild
import io.github.sofianbll.oortnx.shelf.ShelfError
import io.github.sofianbll.oortnx.shelf.ShelfPlatform
import java.io.File
import java.nio.file.Files
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CloudTest {
    private val build = ShelfBuild(
        "0100000000010000", "Orbit « 1 » \"x\"\n", ShelfPlatform.ANDROID, "1.0", "c", "29", "arm64", listOf("vulkan1.1"), 0, "game.apk", "org.nx2a.orbit", 7L,
        "c".repeat(64), 12, listOf(ShelfBuild.Entry("data/romfs.bin", 5, "a".repeat(64)), ShelfBuild.Entry("game.apk", 7, "b".repeat(64))), "d".repeat(64), 1, "id",
    )

    @Test fun `the queue survives the process, in order, one at a time`() {
        val file = File(Files.createTempDirectory("oort").toFile(), "queue.json")
        val queue = CloudQueue(file)
        queue.add(build)
        queue.add(build)
        assertEquals(1, queue.tasks.size)
        queue.set(build.titleID, CloudTask.State.RUNNING)
        assertNull(queue.next, "one at a time")
        val again = CloudQueue(file)
        assertEquals(build, again.next?.build, "what was running waits again")
        again.set(build.titleID, CloudTask.State.FAILED, ShelfError.NoSpace(12))
        val third = CloudQueue(file).tasks.single()
        assertEquals(Triple("noSpace", 12L, CloudTask.State.FAILED), Triple(third.reason, third.needed, third.state))
        again.remove(build.titleID)
        assertTrue(CloudQueue(file).tasks.isEmpty())
    }

    @Test fun `a damaged queue is an empty one`() {
        val file = File(Files.createTempDirectory("oort").toFile(), "queue.json")
        for (text in listOf("", "{", "[1]", "[{\"build\":{}}]")) {
            file.writeText(text)
            assertTrue(CloudQueue(file).tasks.isEmpty(), text)
        }
    }

    @Test fun `only Oort NX is answered`() {
        assertTrue(CloudGuard.isOort("io.github.sofianbll.oortnx.alpha"))
        for (other in listOf(null, "", "org.example", "io.github.sofianbll.oortnx.alpha.cloud", "io.github.sofianbll.oortnx")) assertFalse(CloudGuard.isOort(other))
    }

    @Test fun `an APK that is not the one the manifest names is refused`() {
        val good = listOf("c".repeat(64))
        assertNull(CloudInstalls.refusal(build, "org.nx2a.orbit", 7, good))
        assertEquals(ShelfError.WrongDigest, CloudInstalls.refusal(build, "org.nx2a.other", 7, good))
        assertEquals(ShelfError.WrongDigest, CloudInstalls.refusal(build, "org.nx2a.orbit", 6, good))
        assertEquals(ShelfError.Unsigned, CloudInstalls.refusal(build, "org.nx2a.orbit", 7, listOf("e".repeat(64))))
        assertEquals(ShelfError.Unsigned, CloudInstalls.refusal(build, "org.nx2a.orbit", 7, good + "e".repeat(64)))
        assertEquals(ShelfError.Unsigned, CloudInstalls.refusal(build, "org.nx2a.orbit", 7, emptyList()))
    }

    @Test fun `data goes in data and never over a save`() {
        assertTrue(CloudInstalls.isDataPath("data/romfs/a.bin"))
        for (path in listOf("romfs/a", "data/../x", "data/save/slot", "data/Save_device/x", "/data/x", "other.bin")) assertFalse(CloudInstalls.isDataPath(path), path)
    }

    @Test fun `what is written is read again as it was`() {
        val value = mapOf("a" to listOf(1L, true, null, "é\"\\\n"), "b" to emptyMap<String, Any>())
        assertEquals(value, Json.read(CloudQueue.write(value).toByteArray()))
    }

    @Test fun `a code as a camera sees it is read`() {
        val text = "{\"oort\":\"drive-1\",\"kind\":\"desktop\",\"client\":\"1-a.apps.googleusercontent.com\",\"folder\":\"ROOT\",\"signer\":\"${"A".repeat(124)}\"}"
        val matrix = QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 700, 700)
        val stride = 1344
        val picture = ByteArray(stride * 720) { i ->
            val x = i % stride - 200
            val y = i / stride - 10
            if (x in 0 until 700 && y in 0 until 700 && matrix[x, y]) 30 else 200.toByte()
        }
        assertEquals(text, ScanActivity.read(picture, stride, 720, 1280))
        assertNull(ScanActivity.read(ByteArray(stride * 720) { 120 }, stride, 720, 1280))
    }
}
