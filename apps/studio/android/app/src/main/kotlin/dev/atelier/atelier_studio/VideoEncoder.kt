package dev.atelier.atelier_studio

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import java.io.File

/// Time-lapse frames (JPEG files, in order) into an H.264 MP4. Frames go
/// in as YUV buffers with their own timestamps, so none is dropped and the
/// video runs at exactly [fps].
object VideoEncoder {
    private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
    private const val TIMEOUT = 10_000L

    fun encode(
        frames: List<String>, output: String, width: Int, height: Int, fps: Int, audio: String? = null,
    ): Boolean {
        val sound = audio?.let { AudioEncoder.aac(it) }
        if (frames.isEmpty() || width < 2 || height < 2 || width % 2 != 0 || height % 2 != 0) return false
        File(output).delete()
        val format = MediaFormat.createVideoFormat(MIME, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, maxOf(2_000_000, (width.toLong() * height * fps / 5).toInt()))
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = MediaCodec.createEncoderByType(MIME)
        val muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        var muxing = false
        var samples = 0
        val info = MediaCodec.BufferInfo()

        /// Moves finished output into the file; with [end], until the last.
        fun drain(end: Boolean) {
            while (true) {
                val index = codec.dequeueOutputBuffer(info, TIMEOUT)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!end) return
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(codec.outputFormat)
                        val soundTrack = sound?.let { muxer.addTrack(it.first) }
                        muxer.start()
                        muxing = true
                        if (sound != null && soundTrack != null) {
                            for ((bytes, at) in sound.second) {
                                muxer.writeSampleData(soundTrack, java.nio.ByteBuffer.wrap(bytes), at)
                            }
                        }
                    }
                    index >= 0 -> {
                        val buffer = codec.getOutputBuffer(index)
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (buffer != null && info.size > 0 && muxing) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            muxer.writeSampleData(track, buffer, info)
                            samples++
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        fun nextInput(): Int {
            while (true) {
                val index = codec.dequeueInputBuffer(TIMEOUT)
                if (index >= 0) return index
                drain(false)
            }
        }

        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val pixels = IntArray(width * height)
            for ((n, path) in frames.withIndex()) {
                val decoded = BitmapFactory.decodeFile(path) ?: continue
                val bitmap = if (decoded.width == width && decoded.height == height) decoded
                    else Bitmap.createScaledBitmap(decoded, width, height, true).also { decoded.recycle() }
                bitmap.getPixels(pixels, 0, width, 0, 0, width, height)
                bitmap.recycle()
                val index = nextInput()
                val image = codec.getInputImage(index) ?: return false
                val (yPlane, uPlane, vPlane) = image.planes
                val y = yPlane.buffer
                val u = uPlane.buffer
                val v = vPlane.buffer
                for (row in 0 until height) {
                    for (col in 0 until width) {
                        val p = pixels[row * width + col]
                        val r = (p shr 16) and 0xff
                        val g = (p shr 8) and 0xff
                        val b = p and 0xff
                        y.put(row * yPlane.rowStride + col * yPlane.pixelStride,
                            (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
                        if (row % 2 == 0 && col % 2 == 0) {
                            val at = (row / 2)
                            val cu = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                            val cv = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                            u.put(at * uPlane.rowStride + (col / 2) * uPlane.pixelStride, cu.toByte())
                            v.put(at * vPlane.rowStride + (col / 2) * vPlane.pixelStride, cv.toByte())
                        }
                    }
                }
                codec.queueInputBuffer(index, 0, width * height * 3 / 2, n * 1_000_000L / fps, 0)
                drain(false)
            }
            codec.queueInputBuffer(nextInput(), 0, 0, frames.size * 1_000_000L / fps,
                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
            return samples > 0
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            try { if (muxing) muxer.stop() } catch (_: Exception) {}
            muxer.release()
        }
    }
}

/// A WAV (16-bit PCM) encoded to AAC: the track's format and its samples,
/// ready for a muxer.
object AudioEncoder {
    private const val MIME = MediaFormat.MIMETYPE_AUDIO_AAC
    private const val TIMEOUT = 10_000L

    fun aac(wav: String): Pair<MediaFormat, List<Pair<ByteArray, MediaCodec.BufferInfo>>>? {
        val bytes = File(wav).readBytes()
        val head = java.nio.ByteBuffer.wrap(bytes).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        if (bytes.size < 12 || String(bytes, 0, 4) != "RIFF") return null
        var at = 12
        var rate = 48000
        var channels = 2
        var data = -1
        var size = 0
        while (at + 8 <= bytes.size) {
            val tag = String(bytes, at, 4)
            val length = head.getInt(at + 4)
            if (tag == "fmt ") {
                channels = head.getShort(at + 10).toInt()
                rate = head.getInt(at + 12)
            } else if (tag == "data") {
                data = at + 8
                size = minOf(length, bytes.size - data)
                break
            }
            at += 8 + length + (length and 1)
        }
        if (data < 0) return null
        val format = MediaFormat.createAudioFormat(MIME, rate, channels).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, 160_000)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)
        }
        val codec = MediaCodec.createEncoderByType(MIME)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()
        val out = mutableListOf<Pair<ByteArray, MediaCodec.BufferInfo>>()
        var outFormat: MediaFormat? = null
        val info = MediaCodec.BufferInfo()
        var read = 0
        var inputDone = false
        val frameBytes = 2 * channels
        try {
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT)
                    if (i >= 0) {
                        val buffer = codec.getInputBuffer(i)!!
                        val n = minOf(buffer.capacity() - buffer.capacity() % frameBytes, size - read)
                        val time = read.toLong() / frameBytes * 1_000_000L / rate
                        if (n <= 0) {
                            codec.queueInputBuffer(i, 0, 0, time, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            buffer.put(bytes, data + read, n)
                            codec.queueInputBuffer(i, 0, n, time, 0)
                            read += n
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outFormat = codec.outputFormat
                } else if (o >= 0) {
                    if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0 && info.size > 0) {
                        val buffer = codec.getOutputBuffer(o)!!
                        val copy = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(copy)
                        val meta = MediaCodec.BufferInfo().apply {
                            set(0, info.size, info.presentationTimeUs, info.flags)
                        }
                        out.add(copy to meta)
                    }
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            codec.stop()
            codec.release()
        }
        return outFormat?.let { it to out }
    }
}
