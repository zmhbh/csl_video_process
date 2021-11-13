package com.chanshila.video_process

import android.content.Context
import android.net.Uri
import android.util.Log
import com.otaliastudios.transcoder.Transcoder
import com.otaliastudios.transcoder.TranscoderListener
import com.otaliastudios.transcoder.source.TrimDataSource
import com.otaliastudios.transcoder.source.UriDataSource
import com.otaliastudios.transcoder.strategy.DefaultAudioStrategy
import com.otaliastudios.transcoder.strategy.DefaultVideoStrategy
import com.otaliastudios.transcoder.strategy.RemoveTrackStrategy
import com.otaliastudios.transcoder.strategy.TrackStrategy
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import com.otaliastudios.transcoder.internal.Logger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.Future

/**
 * VideoProcessPlugin
 */
class VideoProcessPlugin : MethodCallHandler, FlutterPlugin {


    private var _context: Context? = null
    private var _channel: MethodChannel? = null
    private val TAG = "VideoProcessPlugin"
    private val LOG = Logger(TAG)
    private var transcodeFuture:Future<Void>? = null
    var channelName = "csl_video_process"
    private val utility = Utility(channelName)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val context = _context;
        val channel = _channel;

        if (context == null || channel == null) {
            Log.w(TAG, "Calling VideoProcess plugin before initialization")
            return
        }

        when (call.method) {
            "getByteThumbnail" -> {
                val path = call.argument<String>("path")
                val quality = call.argument<Int>("quality")!!
                val position = call.argument<Int>("position")!! // to long
                ThumbnailUtility(channelName).getByteThumbnail(path!!, quality, position.toLong(), result)
            }
            "getFileThumbnail" -> {
                val path = call.argument<String>("path")
                val sessionId = call.argument<Long>("sessionId")
                val quality = call.argument<Int>("quality")!!
                val position = call.argument<Int>("position")!! // to long
                ThumbnailUtility("video_compress").getFileThumbnail(context, path!!, sessionId!!, quality,
                        position.toLong(), result)
            }
            "getMediaInfo" -> {
                val path = call.argument<String>("path")
                result.success(Utility(channelName).getMediaInfoJson(context, path!!).toString())
            }
            "deleteSessionCache" -> {
                val sessionId = call.argument<Long>("sessionId")!!
                result.success(Utility(channelName).deleteSessionCache(context, sessionId, result));
            }
            "setLogLevel" -> {
                val logLevel = call.argument<Int>("logLevel")!!
                Logger.setLogLevel(logLevel)
                result.success(true);
            }
            "cancelCompression" -> {
                transcodeFuture?.cancel(true)
                result.success(false);
            }
            "compressVideo" -> {
                val path = call.argument<String>("path")!!
                val sessionId = call.argument<Long>("sessionId")!!
                val startTimeMs = call.argument<Double>("startTimeMs")
                val endTimeMs = call.argument<Double>("endTimeMs")
                val includeAudio = call.argument<Boolean>("includeAudio") ?: true
                val rotation = call.argument<Int>("rotation") ?: 0
                val tempDir: String = context.getExternalFilesDir("csl_video_process/$sessionId")!!.absolutePath
                val out = System.currentTimeMillis()
                val outputFileName = path.substring(path.lastIndexOf('/'),
                        path.lastIndexOf('.')) +"-" + out + ".mp4"
                val destPath: String = tempDir + outputFileName

                val file = File(tempDir, outputFileName)
                utility.deleteFile(file)


                var videoTrackStrategy: TrackStrategy
                val audioTrackStrategy: TrackStrategy



                videoTrackStrategy = DefaultVideoStrategy.atMost(720)
                        //.keyFrameInterval(15f)
                        .bitRate(1024 * 1024 * 3.0.toLong()) //from 2.0
                        .frameRate(30) // will be capped to the input frameRate
                        .build()

                audioTrackStrategy = if (includeAudio) {
                    val sampleRate = DefaultAudioStrategy.SAMPLE_RATE_AS_INPUT
                    val channels = DefaultAudioStrategy.CHANNELS_AS_INPUT

                    DefaultAudioStrategy.builder()
                        .channels(channels)
                        .sampleRate(sampleRate)
                        .build()
                } else {
                    RemoveTrackStrategy()
                }

                val dataSource = if (startTimeMs != null && endTimeMs != null){
                    val source = UriDataSource(context, Uri.parse(path))
                    // for Transcoder, how trimming works: x second at the beginning, and y seconds at the end:
                    val x = (startTimeMs * 1000).toLong()
                    var y = source.getDurationUs() - (endTimeMs * 1000).toLong()
                    if(y < 0) {
                        y = 0
                    }
                    TrimDataSource(source, x, y)
                }else{
                    UriDataSource(context, Uri.parse(path))
                }


                transcodeFuture = Transcoder.into(destPath!!)
                        .setVideoRotation(rotation)
                        .addDataSource(dataSource)
                        .setAudioTrackStrategy(audioTrackStrategy)
                        .setVideoTrackStrategy(videoTrackStrategy)
                        .setListener(object : TranscoderListener {
                            override fun onTranscodeProgress(progress: Double) {
                                channel.invokeMethod("updateProgress", progress * 100.00)
                            }
                            override fun onTranscodeCompleted(successCode: Int) {
                                channel.invokeMethod("updateProgress", 100.00)
                                val json = Utility(channelName).getMediaInfoJson(context, destPath)
                                json.put("isCancel", false)
                                result.success(json.toString())
                            }

                            override fun onTranscodeCanceled() {
                                result.success(null)
                            }

                            override fun onTranscodeFailed(exception: Throwable) {
                                result.success(null)
                            }
                        }).transcode()
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        init(binding.applicationContext, binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        _channel?.setMethodCallHandler(null)
        _context = null
        _channel = null
    }

    private fun init(context: Context, messenger: BinaryMessenger) {
        val channel = MethodChannel(messenger, channelName)
        channel.setMethodCallHandler(this)
        _context = context
        _channel = channel
    }

    companion object {
        private const val TAG = "csl_video_process"

        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val instance = VideoProcessPlugin()
            instance.init(registrar.context(), registrar.messenger())
        }
    }

}
