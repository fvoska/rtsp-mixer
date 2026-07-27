package tech.voska.rtsp_mixer.levelmeter

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.sqrt

/**
 * Receives every decoded PCM buffer from the sidecar player's audio pipeline
 * (via [TeeAudioProcessor]) and reduces it to windowed RMS + peak levels in
 * dBFS. The tap sits BEFORE the AudioTrack volume stage, so it sees
 * full-scale samples even though the sidecar plays at volume 0.
 *
 * Called on ExoPlayer's audio processing thread — [onWindow] must hop to the
 * main thread itself. Keep this class allocation-free per buffer.
 */
@OptIn(UnstableApi::class)
internal class PcmLevelTap(
    private val onWindow: (rmsDb: Double, peakDb: Double) -> Unit,
) : TeeAudioProcessor.AudioBufferSink {

    private var sampleRate = 48_000
    private var channelCount = 1
    private var encoding = C.ENCODING_PCM_16BIT

    private var sumSquares = 0.0
    private var peak = 0.0
    private var sampleCount = 0

    override fun flush(sampleRate: Int, channelCount: Int, encoding: Int) {
        this.sampleRate = sampleRate
        this.channelCount = channelCount
        this.encoding = encoding
        sumSquares = 0.0
        peak = 0.0
        sampleCount = 0
    }

    override fun handleBuffer(buffer: ByteBuffer) {
        // DefaultAudioSink feeds processors 16-bit PCM unless float output is
        // explicitly enabled (it isn't). Anything else: skip rather than
        // misread — the Dart side falls back to the bitrate proxy on silence.
        if (encoding != C.ENCODING_PCM_16BIT) return

        val buf = buffer.asReadOnlyBuffer().order(ByteOrder.LITTLE_ENDIAN)
        while (buf.remaining() >= 2) {
            val v = buf.short / 32768.0
            sumSquares += v * v
            val a = abs(v)
            if (a > peak) peak = a
            sampleCount++
        }

        // Emit roughly every 100 ms of audio (~10 Hz).
        val windowSamples = sampleRate * channelCount / 10
        if (windowSamples > 0 && sampleCount >= windowSamples) {
            val rms = sqrt(sumSquares / sampleCount)
            onWindow(ampToDb(rms), ampToDb(peak))
            sumSquares = 0.0
            peak = 0.0
            sampleCount = 0
        }
    }

    private fun ampToDb(amplitude: Double): Double =
        // Floor at -100 dBFS so digital silence never produces -Infinity,
        // which would not survive the platform channel as a finite double.
        if (amplitude <= 1e-5) -100.0 else 20.0 * log10(amplitude)
}
