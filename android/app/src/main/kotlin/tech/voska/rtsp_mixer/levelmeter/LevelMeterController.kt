package tech.voska.rtsp_mixer.levelmeter

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Process-wide owner of the per-camera [CameraLevelAnalyzer]s and their
 * Flutter channels.
 *
 * A singleton (not activity-scoped) because the Flutter engine — and the
 * monitoring session — outlives the activity when the screen is off
 * overnight. [attach] is idempotent: a recreated activity re-registers the
 * channels against the same running analyzers.
 *
 * Channel contract (Dart side: `services/native_level_meter.dart`):
 *  - MethodChannel `roomtone/level_meter`
 *      start        {cameras: [{id: String, urls: [String]}]} — replaces all
 *      startCamera  {id: String, urls: [String]}              — replaces one
 *      stopCamera   {id: String}
 *      stopAll      (no args)
 *  - EventChannel `roomtone/level_meter/events`, map events:
 *      {type: "level",  cameraId, rmsDb: Double, peakDb: Double}
 *      {type: "status", cameraId, state: "active"|"retrying", detail: String?}
 *
 * Defensive contract (CLAUDE.md): malformed calls answer with a channel
 * error, never an exception; analyzer failures only ever log and retry.
 */
internal object LevelMeterController : CameraLevelAnalyzer.Listener {
    private const val TAG = "LevelMeter"

    private val analyzers = mutableMapOf<String, CameraLevelAnalyzer>()
    private var appContext: Context? = null
    private var eventSink: EventChannel.EventSink? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext

        MethodChannel(messenger, "roomtone/level_meter").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        stopAll()
                        val cameras = call.argument<List<Map<String, Any?>>>("cameras").orEmpty()
                        for (cam in cameras) startCameraFromArgs(cam)
                        result.success(analyzers.size)
                    }
                    "startCamera" -> {
                        val args = call.arguments as? Map<*, *>
                        @Suppress("UNCHECKED_CAST")
                        startCameraFromArgs(args as? Map<String, Any?> ?: emptyMap())
                        result.success(true)
                    }
                    "stopCamera" -> {
                        val id = call.argument<String>("id")
                        if (id != null) analyzers.remove(id)?.stop()
                        result.success(true)
                    }
                    "stopAll" -> {
                        stopAll()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            } catch (t: Throwable) {
                Log.w(TAG, "method ${call.method} failed: $t")
                result.error("level_meter_error", t.toString(), null)
            }
        }

        EventChannel(messenger, "roomtone/level_meter/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    private fun startCameraFromArgs(args: Map<String, Any?>) {
        val context = appContext ?: return
        val id = args["id"] as? String ?: return
        val urls = (args["urls"] as? List<*>).orEmpty().filterIsInstance<String>()
        if (urls.isEmpty()) {
            Log.w(TAG, "$id: no analyzer URLs supplied — skipping")
            return
        }
        analyzers.remove(id)?.stop()
        val analyzer = CameraLevelAnalyzer(context, id, urls, this)
        analyzers[id] = analyzer
        analyzer.start()
    }

    private fun stopAll() {
        for (analyzer in analyzers.values) analyzer.stop()
        analyzers.clear()
    }

    // CameraLevelAnalyzer.Listener — both callbacks arrive on the main
    // thread (required by EventChannel).

    override fun onLevel(cameraId: String, rmsDb: Double, peakDb: Double) {
        try {
            eventSink?.success(
                mapOf(
                    "type" to "level",
                    "cameraId" to cameraId,
                    "rmsDb" to rmsDb,
                    "peakDb" to peakDb,
                ),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "level event delivery failed (ignored): $t")
        }
    }

    override fun onStatus(cameraId: String, state: String, detail: String?) {
        try {
            eventSink?.success(
                mapOf(
                    "type" to "status",
                    "cameraId" to cameraId,
                    "state" to state,
                    "detail" to detail,
                ),
            )
        } catch (t: Throwable) {
            Log.w(TAG, "status event delivery failed (ignored): $t")
        }
    }
}
