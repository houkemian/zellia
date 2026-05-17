package one.dothings.zellia

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

/**
 * Android notification channels reliably play WAV/OGG/MP3 — not M4A/AAC.
 * Decode caregiver m4a to 16-bit PCM WAV for [FileProvider] notification URIs.
 */
object FamilyVoiceSoundConverter {
    private const val TAG = "FamilyVoiceSound"

    fun ensureWavForNotification(inputPath: String): String? {
        val input = File(inputPath)
        if (!input.exists() || input.length() == 0L) return null
        val wav = File(input.parent, "${input.nameWithoutExtension}_notify.wav")
        if (wav.exists() && wav.length() > 44L) {
            return wav.absolutePath
        }
        return try {
            decodeToWav(input, wav)
            if (wav.exists() && wav.length() > 44L) wav.absolutePath else null
        } catch (e: Exception) {
            Log.e(TAG, "wav convert failed path=$inputPath: ${e.message}")
            null
        }
    }

    private fun decodeToWav(input: File, output: File) {
        val extractor = MediaExtractor()
        extractor.setDataSource(input.absolutePath)
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val trackFormat = extractor.getTrackFormat(i)
            val mime = trackFormat.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                format = trackFormat
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            throw IllegalStateException("no audio track in ${input.name}")
        }
        extractor.selectTrack(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)
            ?: throw IllegalStateException("missing mime")
        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val pcmChunks = mutableListOf<ByteArray>()
        var totalPcmBytes = 0
        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channelCount = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val bufferInfo = MediaCodec.BufferInfo()
        var inputDone = false

        while (true) {
            if (!inputDone) {
                val inIndex = codec.dequeueInputBuffer(10_000)
                if (inIndex >= 0) {
                    val inputBuffer: ByteBuffer =
                        codec.getInputBuffer(inIndex)
                            ?: throw IllegalStateException("null input buffer")
                    val sampleSize = extractor.readSampleData(inputBuffer, 0)
                    if (sampleSize < 0) {
                        codec.queueInputBuffer(
                            inIndex,
                            0,
                            0,
                            0L,
                            MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                        )
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(
                            inIndex,
                            0,
                            sampleSize,
                            extractor.sampleTime,
                            0,
                        )
                        extractor.advance()
                    }
                }
            }

            val outIndex = codec.dequeueOutputBuffer(bufferInfo, 10_000)
            when {
                outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    val newFormat = codec.outputFormat
                    sampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channelCount = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
                outIndex >= 0 -> {
                    val outBuffer: ByteBuffer =
                        codec.getOutputBuffer(outIndex)
                            ?: throw IllegalStateException("null output buffer")
                    val chunk = ByteArray(bufferInfo.size)
                    outBuffer.get(chunk)
                    outBuffer.clear()
                    pcmChunks.add(chunk)
                    totalPcmBytes += chunk.size
                    codec.releaseOutputBuffer(outIndex, false)
                    if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        break
                    }
                }
            }
        }

        codec.stop()
        codec.release()
        extractor.release()
        writeWav(output, pcmChunks, totalPcmBytes, sampleRate, channelCount)
        Log.i(TAG, "wav ready ${output.name} bytes=${output.length()} sr=$sampleRate ch=$channelCount")
    }

    private fun writeWav(
        output: File,
        chunks: List<ByteArray>,
        pcmSize: Int,
        sampleRate: Int,
        channels: Int,
    ) {
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        FileOutputStream(output).use { fos ->
            fos.write("RIFF".toByteArray(Charsets.US_ASCII))
            fos.write(intLe(36 + pcmSize))
            fos.write("WAVE".toByteArray(Charsets.US_ASCII))
            fos.write("fmt ".toByteArray(Charsets.US_ASCII))
            fos.write(intLe(16))
            fos.write(shortLe(1))
            fos.write(shortLe(channels))
            fos.write(intLe(sampleRate))
            fos.write(intLe(byteRate))
            fos.write(shortLe(channels * bitsPerSample / 8))
            fos.write(shortLe(bitsPerSample))
            fos.write("data".toByteArray(Charsets.US_ASCII))
            fos.write(intLe(pcmSize))
            for (chunk in chunks) {
                fos.write(chunk)
            }
        }
    }

    private fun intLe(value: Int): ByteArray =
        byteArrayOf(
            (value and 0xff).toByte(),
            (value shr 8 and 0xff).toByte(),
            (value shr 16 and 0xff).toByte(),
            (value shr 24 and 0xff).toByte(),
        )

    private fun shortLe(value: Int): ByteArray =
        byteArrayOf(
            (value and 0xff).toByte(),
            (value shr 8 and 0xff).toByte(),
        )
}
