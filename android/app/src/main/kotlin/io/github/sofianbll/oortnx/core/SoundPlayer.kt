package io.github.sofianbll.oortnx.core

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import java.util.concurrent.Executors

/**
 * Plays OortSynth's PCM. The first play of a sound makes it (a few hundred milliseconds off the main thread,
 * because of the reverb); later plays reuse it. No file is read or written.
 */
class SoundPlayer(private val prefs: Prefs) {
    private val worker = Executors.newSingleThreadExecutor { Thread(it, "oort-sound").apply { isDaemon = true } }
    private val cache = HashMap<String, ShortArray?>()
    private var track: AudioTrack? = null

    fun play(event: SoundEvent, step: Int = 0) {
        if (!prefs.sound) return
        val pack = prefs.pack
        worker.execute {
            val key = "$pack/$event/${step % 8}"
            val pcm = cache.getOrPut(key) { OortSynth.of(pack)?.pcm(event, step) } ?: return@execute
            start(pcm)
        }
    }

    private fun start(pcm: ShortArray) {
        track?.release()
        val format = AudioFormat.Builder()
            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(OortSynth.RATE.toInt())
            .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
            .build()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val next = AudioTrack.Builder()
            .setAudioAttributes(attributes)
            .setAudioFormat(format)
            .setBufferSizeInBytes(pcm.size * 2)
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()
        next.write(pcm, 0, pcm.size)
        next.play()
        track = next
    }

    fun release() {
        worker.execute { track?.release(); track = null }
        worker.shutdown()
    }
}
