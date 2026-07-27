package tech.voska.rtsp_mixer

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import tech.voska.rtsp_mixer.levelmeter.LevelMeterController

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Level-meter sidecar channels. Idempotent — the controller is a
        // singleton so an activity recreation re-binds the same analyzers.
        LevelMeterController.attach(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }
}
