package dev.atelier.atelier_studio

import android.graphics.Bitmap
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaPlayer
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/// Movie media: what a file holds, its pictures as small JPEG proxies, its
/// sound as 48 kHz stereo 16-bit WAV, and playing a WAV.
object MediaTools {
    private const val RATE = 48000
    private const val TIMEOUT = 10_000L

    fun probe(path: String): Map<String, Any> {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            fun key(k: Int) = r.extractMetadata(k)
            val rotation = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            var w = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var h = key(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) w = h.also { h = w }
            val duration = key(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val hasVideo = key(MediaMetadataRetriever.METADATA_KEY_HAS_VIDEO) == "yes"
            val hasAudio = key(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            var fps = 30.0
            val ex = MediaExtractor()
            try {
                ex.setDataSource(path)
                for (i in 0 until ex.trackCount) {
                    val f = ex.getTrackFormat(i)
                    if (f.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true &&
                        f.containsKey(MediaFormat.KEY_FRAME_RATE)
                    ) fps = f.getInteger(MediaFormat.KEY_FRAME_RATE).toDouble()
                }
            } finally {
                ex.release()
            }
            return mapOf(
                "width" to w, "height" to h, "durationMs" to duration,
                "fps" to fps, "hasVideo" to hasVideo, "hasAudio" to hasAudio,
            )
        } finally {
            r.release()
        }
    }

    /// The video's frames [fps] a second, at most [maxSide] pixels, as
    /// `outDir/00000.jpg` …; how many were written. The video is decoded once,
    /// start to end; should that fail, frame by frame instead.
    fun frames(path: String, outDir: String, fps: Double, maxSide: Int): Int =
        try {
            decodeFrames(path, outDir, fps, maxSide)
        } catch (e: Exception) {
            seekFrames(path, outDir, fps, maxSide)
        }

    private fun decodeFrames(path: String, outDir: String, fps: Double, maxSide: Int): Int {
        val dir = File(outDir).apply { mkdirs() }
        val ex = MediaExtractor()
        ex.setDataSource(path)
        val track = (0 until ex.trackCount).first {
            ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true
        }
        ex.selectTrack(track)
        val format = ex.getTrackFormat(track)
        val rotation = if (format.containsKey(MediaFormat.KEY_ROTATION)) format.getInteger(MediaFormat.KEY_ROTATION) else {
            val r = MediaMetadataRetriever()
            try {
                r.setDataSource(path)
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            } finally {
                r.release()
            }
        }
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var next = 0
        var last: Bitmap? = null
        try {
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT)
                    if (i >= 0) {
                        val n = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT)
                if (o < 0) continue
                val end = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                // A frame stands for every proxy time up to its own.
                val due = info.presentationTimeUs >= (next * 1_000_000.0 / fps).toLong()
                if (info.size > 0 && due) {
                    val image = codec.getOutputImage(o)
                    if (image != null) {
                        val picture = toBitmap(image, maxSide, rotation)
                        image.close()
                        last?.recycle()
                        last = picture
                        while (next * 1_000_000.0 / fps <= info.presentationTimeUs) {
                            write(picture, File(dir, "%05d.jpg".format(next)))
                            next++
                        }
                    }
                }
                codec.releaseOutputBuffer(o, false)
                if (end) break
            }
        } finally {
            codec.stop()
            codec.release()
            ex.release()
        }
        last?.recycle()
        if (next == 0) throw IllegalStateException("No frames decoded")
        return next
    }

    private fun write(bitmap: Bitmap, file: File) =
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) }

    /// A decoded YUV 4:2:0 [image] as RGB, every step-th pixel so it is at
    /// most [maxSide] across, turned upright by [rotation] degrees.
    private fun toBitmap(image: android.media.Image, maxSide: Int, rotation: Int): Bitmap {
        val crop = image.cropRect
        val step = maxOf(1, Math.ceil(maxOf(crop.width(), crop.height()).toDouble() / maxSide).toInt())
        val w = crop.width() / step
        val h = crop.height() / step
        val (yp, up, vp) = image.planes
        val y = yp.buffer
        val u = up.buffer
        val v = vp.buffer
        val pixels = IntArray(w * h)
        for (row in 0 until h) {
            val sy = crop.top + row * step
            for (col in 0 until w) {
                val sx = crop.left + col * step
                val yy = (y.get(sy * yp.rowStride + sx * yp.pixelStride).toInt() and 0xff) - 16
                val ci = (sy / 2) * up.rowStride + (sx / 2) * up.pixelStride
                val cu = (u.get(ci).toInt() and 0xff) - 128
                val cv = (v.get((sy / 2) * vp.rowStride + (sx / 2) * vp.pixelStride).toInt() and 0xff) - 128
                val c = 298 * maxOf(0, yy)
                val r = ((c + 409 * cv + 128) shr 8).coerceIn(0, 255)
                val g = ((c - 100 * cu - 208 * cv + 128) shr 8).coerceIn(0, 255)
                val b = ((c + 516 * cu + 128) shr 8).coerceIn(0, 255)
                pixels[row * w + col] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val bitmap = Bitmap.createBitmap(pixels, w, h, Bitmap.Config.ARGB_8888)
        if (rotation % 360 == 0) return bitmap
        val turn = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
        return Bitmap.createBitmap(bitmap, 0, 0, w, h, turn, true).also { bitmap.recycle() }
    }

    private fun seekFrames(path: String, outDir: String, fps: Double, maxSide: Int): Int {
        val dir = File(outDir).apply { mkdirs() }
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            val duration = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            val count = maxOf(1, (duration / 1000.0 * fps).toInt())
            var written = 0
            for (i in 0 until count) {
                val us = (i * 1_000_000.0 / fps).toLong()
                val frame = r.getFrameAtTime(us, MediaMetadataRetriever.OPTION_CLOSEST) ?: continue
                val scale = minOf(1.0, maxSide.toDouble() / maxOf(frame.width, frame.height))
                val small = if (scale < 1.0) {
                    Bitmap.createScaledBitmap(
                        frame, maxOf(1, (frame.width * scale).toInt()), maxOf(1, (frame.height * scale).toInt()), true,
                    ).also { frame.recycle() }
                } else frame
                FileOutputStream(File(dir, "%05d.jpg".format(i))).use {
                    small.compress(Bitmap.CompressFormat.JPEG, 85, it)
                }
                small.recycle()
                written = i + 1
            }
            return written
        } finally {
            r.release()
        }
    }

    /// The first audio track decoded to 48 kHz stereo 16-bit WAV at [out].
    fun audio(path: String, out: String): Boolean {
        val ex = MediaExtractor()
        ex.setDataSource(path)
        val track = (0 until ex.trackCount).firstOrNull {
            ex.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: run { ex.release(); return false }
        ex.selectTrack(track)
        val format = ex.getTrackFormat(track)
        val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        codec.configure(format, null, null, 0)
        codec.start()
        val pcm = ByteArrayOutputStream()
        var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        try {
            while (true) {
                if (!inputDone) {
                    val i = codec.dequeueInputBuffer(TIMEOUT)
                    if (i >= 0) {
                        val n = ex.readSampleData(codec.getInputBuffer(i)!!, 0)
                        if (n < 0) {
                            codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            codec.queueInputBuffer(i, 0, n, ex.sampleTime, 0)
                            ex.advance()
                        }
                    }
                }
                val o = codec.dequeueOutputBuffer(info, TIMEOUT)
                if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    rate = codec.outputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = codec.outputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                } else if (o >= 0) {
                    val buf = codec.getOutputBuffer(o)!!
                    val bytes = ByteArray(info.size)
                    buf.position(info.offset)
                    buf.get(bytes)
                    pcm.write(bytes)
                    codec.releaseOutputBuffer(o, false)
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
        } finally {
            codec.stop()
            codec.release()
            ex.release()
        }
        val source = ByteBuffer.wrap(pcm.toByteArray()).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
        val frames = source.remaining() / channels
        val outFrames = (frames.toLong() * RATE / rate).toInt()
        val stereo = ShortArray(outFrames * 2)
        for (i in 0 until outFrames) {
            val at = i.toDouble() * rate / RATE
            val a = minOf(frames - 1, at.toInt())
            val b = minOf(frames - 1, a + 1)
            val t = at - a
            for (ch in 0 until 2) {
                val c = if (channels == 1) 0 else ch
                val va = source.get(a * channels + c)
                val vb = source.get(b * channels + c)
                stereo[i * 2 + ch] = (va + (vb - va) * t).toInt().toShort()
            }
        }
        writeWav(out, stereo)
        return true
    }

    private fun writeWav(out: String, samples: ShortArray) {
        val data = samples.size * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            put("RIFF".toByteArray()); putInt(36 + data); put("WAVE".toByteArray())
            put("fmt ".toByteArray()); putInt(16); putShort(1); putShort(2)
            putInt(RATE); putInt(RATE * 4); putShort(4); putShort(16)
            put("data".toByteArray()); putInt(data)
        }
        FileOutputStream(out).use { f ->
            f.write(header.array())
            val body = ByteBuffer.allocate(data).order(ByteOrder.LITTLE_ENDIAN)
            body.asShortBuffer().put(samples)
            f.write(body.array())
        }
    }

    /// Every page of the PDF at [path] drawn (vectors and all) on white, at
    /// most [maxSide] pixels across, as `outDir/page000.png` …; their paths.
    fun pdfPages(path: String, outDir: String, maxSide: Int): List<String> {
        val dir = File(outDir).apply { mkdirs() }
        val fd = android.os.ParcelFileDescriptor.open(
            File(path), android.os.ParcelFileDescriptor.MODE_READ_ONLY,
        )
        val renderer = android.graphics.pdf.PdfRenderer(fd)
        val out = mutableListOf<String>()
        try {
            for (i in 0 until renderer.pageCount) {
                renderer.openPage(i).use { page ->
                    val scale = maxSide.toDouble() / maxOf(page.width, page.height)
                    val w = maxOf(1, (page.width * scale).toInt())
                    val h = maxOf(1, (page.height * scale).toInt())
                    val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    bitmap.eraseColor(android.graphics.Color.WHITE)
                    page.render(bitmap, null, null, android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    val file = File(dir, "page%03d.png".format(i))
                    FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    bitmap.recycle()
                    out.add(file.path)
                }
            }
        } finally {
            renderer.close()
            fd.close()
        }
        return out
    }

    private var player: MediaPlayer? = null
    private var playing: String? = null

    /// [path] from [offsetMs]; with [lengthMs], only that long (scrubbing).
    fun play(path: String, offsetMs: Int, lengthMs: Int?) {
        val p = if (playing == path && player != null) player!! else {
            stop()
            MediaPlayer().apply { setDataSource(path); prepare() }.also {
                player = it
                playing = path
            }
        }
        // Start once the seek is done: before that the player reports 0.
        p.setOnSeekCompleteListener { if (player === it) it.start() }
        p.seekTo(offsetMs.toLong(), MediaPlayer.SEEK_CLOSEST)
        if (lengthMs != null) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (player === p && p.isPlaying) p.pause()
            }, lengthMs.toLong())
        }
    }

    fun stop() {
        player?.let { if (it.isPlaying) it.pause() }
    }

    /// Where the sound is now (ms), while it plays.
    fun position(): Int? = player?.takeIf { it.isPlaying }?.currentPosition

    fun release() {
        player?.release()
        player = null
        playing = null
    }
}
