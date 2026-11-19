package dev.atelier.atelier_studio

import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artblend/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }
        // Movie media: reading and decoding take a while, off the main thread.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artblend/media")
            .setMethodCallHandler { call, result ->
                val path = call.argument<String>("path") ?: ""
                Thread {
                    val value: Any? = try {
                        when (call.method) {
                            "probe" -> MediaTools.probe(path)
                            "frames" -> MediaTools.frames(
                                path,
                                call.argument<String>("out") ?: "",
                                call.argument<Double>("fps") ?: 30.0,
                                call.argument<Int>("maxSide") ?: 640,
                            )
                            "audio" -> MediaTools.audio(path, call.argument<String>("out") ?: "")
                            "pdfPages" -> MediaTools.pdfPages(
                                path,
                                call.argument<String>("out") ?: "",
                                call.argument<Int>("maxSide") ?: 4096,
                            )
                            else -> Unit
                        }
                    } catch (e: Exception) {
                        null
                    }
                    Handler(Looper.getMainLooper()).post {
                        if (value == Unit) result.notImplemented() else result.success(value)
                    }
                }.start()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artblend/audio")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "play" -> MediaTools.play(
                            call.argument<String>("path") ?: "",
                            call.argument<Int>("offsetMs") ?: 0,
                            call.argument<Int>("lengthMs"),
                        )
                        "stop" -> MediaTools.stop()
                        "position" -> return@setMethodCallHandler result.success(MediaTools.position())
                        "release" -> MediaTools.release()
                        else -> return@setMethodCallHandler result.notImplemented()
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }
        // Time-lapse export: encoding takes a while, off the main thread.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "artblend/video")
            .setMethodCallHandler { call, result ->
                if (call.method != "encode") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val frames = call.argument<List<String>>("frames") ?: emptyList()
                val output = call.argument<String>("output") ?: ""
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val fps = call.argument<Int>("fps") ?: 30
                val audio = call.argument<String>("audio")
                Thread {
                    val ok = try {
                        VideoEncoder.encode(frames, output, width, height, fps, audio)
                    } catch (e: Exception) {
                        false
                    }
                    Handler(Looper.getMainLooper()).post { result.success(ok) }
                }.start()
            }
    }
}
