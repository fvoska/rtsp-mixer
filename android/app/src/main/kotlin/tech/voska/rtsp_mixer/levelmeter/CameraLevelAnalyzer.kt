package tech.voska.rtsp_mixer.levelmeter

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.MediaCodecAudioRenderer
import androidx.media3.exoplayer.audio.TeeAudioProcessor
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.rtsp.RtspMediaSource
import java.security.SecureRandom
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocketFactory
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

/**
 * One analysis-only RTSP session for one camera: an audio-only ExoPlayer that
 * decodes the stream, taps decoded PCM via [PcmLevelTap], and reports RMS/peak
 * dBFS windows. It never renders audibly (volume 0 — the tap sits before the
 * volume stage) and is fully independent of the media_kit playback path, so
 * nothing here can ever take down the audio the parent is listening to.
 *
 * Reliability model mirrors the Dart ReconnectSupervisor in miniature:
 *  - candidate URLs are tried in order, advancing on every failure
 *  - exponential backoff between attempts (2s → 60s), reset once healthy
 *  - a PCM-stall watchdog force-restarts when no samples arrive for 20s
 *    (an RTSP session can die silently without a player error)
 *
 * All control flow runs on the main looper; only the PCM tap callback arrives
 * on ExoPlayer's audio thread and immediately hops over.
 */
@OptIn(UnstableApi::class)
internal class CameraLevelAnalyzer(
    private val context: Context,
    val cameraId: String,
    private val urls: List<String>,
    private val listener: Listener,
) {
    interface Listener {
        fun onLevel(cameraId: String, rmsDb: Double, peakDb: Double)
        fun onStatus(cameraId: String, state: String, detail: String?)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var player: ExoPlayer? = null
    private var candidateIndex = 0
    private var backoffMs = INITIAL_BACKOFF_MS
    private var released = false

    @Volatile
    private var lastPcmElapsedMs = 0L

    private val stallWatchdog = object : Runnable {
        override fun run() {
            if (released || player == null) return
            val sinceLastPcm = android.os.SystemClock.elapsedRealtime() - lastPcmElapsedMs
            if (lastPcmElapsedMs != 0L && sinceLastPcm > STALL_THRESHOLD_MS) {
                Log.w(TAG, "$cameraId: no PCM for ${sinceLastPcm}ms — restarting analyzer")
                scheduleRetry("pcm stall (${sinceLastPcm}ms)")
                return
            }
            mainHandler.postDelayed(this, STALL_CHECK_INTERVAL_MS)
        }
    }

    fun start() {
        mainHandler.post {
            if (released) return@post
            openCurrentCandidate()
        }
    }

    fun stop() {
        released = true
        mainHandler.post { teardown() }
    }

    private fun openCurrentCandidate() {
        teardown()
        if (released || urls.isEmpty()) return
        val rawUrl = urls[candidateIndex % urls.size]
        try {
            val tap = PcmLevelTap { rmsDb, peakDb ->
                // Audio thread: stamp liveness, then hop to main for delivery.
                lastPcmElapsedMs = android.os.SystemClock.elapsedRealtime()
                mainHandler.post {
                    if (!released) listener.onLevel(cameraId, rmsDb, peakDb)
                }
            }

            // Audio-only renderer set: no video/text/metadata renderers, so
            // the low-quality stream's video track is never decoded. The tap
            // is injected as an AudioProcessor on the sink.
            val renderersFactory = RenderersFactory { eventHandler, _, audioListener, _, _ ->
                arrayOf<Renderer>(
                    MediaCodecAudioRenderer(
                        context,
                        MediaCodecSelector.DEFAULT,
                        eventHandler,
                        audioListener,
                        DefaultAudioSink.Builder(context)
                            .setAudioProcessors(arrayOf(TeeAudioProcessor(tap)))
                            .build(),
                    ),
                )
            }

            // rtsps:// (manual cameras only — Unifi URLs arrive pre-rewritten
            // to plain rtsp://:7447 by the Dart side): speak RTSP through a
            // TLS socket, the same "rtspx" trick go2rtc uses for Unifi. The
            // ?enableSrtp query is dropped so the payload is plain RTP inside
            // the TLS tunnel (media3 cannot decrypt SRTP).
            val isTls = rawUrl.startsWith("rtsps://", ignoreCase = true)
            val uri = Uri.parse(
                if (isTls) {
                    rawUrl.replaceFirst("rtsps://", "rtsp://").substringBefore("?enableSrtp")
                } else {
                    rawUrl
                },
            )

            val mediaSourceFactory = RtspMediaSource.Factory()
                .setForceUseRtpTcp(true)
                .setTimeoutMs(SOCKET_TIMEOUT_MS)
            if (isTls) mediaSourceFactory.setSocketFactory(trustAllSslSocketFactory())

            val p = ExoPlayer.Builder(context, renderersFactory).build()
            p.addListener(object : Player.Listener {
                override fun onPlayerError(error: PlaybackException) {
                    Log.w(TAG, "$cameraId: analyzer error: ${error.errorCodeName}")
                    scheduleRetry(error.errorCodeName)
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    when (playbackState) {
                        Player.STATE_READY -> {
                            backoffMs = INITIAL_BACKOFF_MS
                            listener.onStatus(cameraId, "active", null)
                        }
                        // A live RTSP stream must never end; treat as a drop.
                        Player.STATE_ENDED -> scheduleRetry("stream ended")
                        else -> Unit
                    }
                }
            })
            // Volume 0 keeps the sidecar inaudible; the PCM tap runs before
            // the AudioTrack volume stage so levels are unaffected.
            p.volume = 0f
            p.setMediaSource(mediaSourceFactory.createMediaSource(MediaItem.fromUri(uri)))
            p.playWhenReady = true
            p.prepare()
            player = p

            lastPcmElapsedMs = 0L
            mainHandler.removeCallbacks(stallWatchdog)
            mainHandler.postDelayed(stallWatchdog, STALL_CHECK_INTERVAL_MS)
            Log.i(TAG, "$cameraId: analyzer opening candidate ${candidateIndex % urls.size}: $uri")
        } catch (t: Throwable) {
            // Nothing in the analyzer is allowed to throw out of the sidecar.
            Log.w(TAG, "$cameraId: analyzer open failed: $t")
            scheduleRetry(t.toString())
        }
    }

    private fun scheduleRetry(cause: String) {
        if (released) return
        teardown()
        candidateIndex++
        val delay = backoffMs
        backoffMs = (backoffMs * 2).coerceAtMost(MAX_BACKOFF_MS)
        listener.onStatus(cameraId, "retrying", cause.take(120))
        mainHandler.postDelayed({ if (!released) openCurrentCandidate() }, delay)
        Log.i(TAG, "$cameraId: analyzer retry in ${delay}ms (cause: $cause)")
    }

    private fun teardown() {
        mainHandler.removeCallbacks(stallWatchdog)
        try {
            player?.release()
        } catch (t: Throwable) {
            Log.w(TAG, "$cameraId: analyzer release failed (ignored): $t")
        }
        player = null
    }

    /**
     * Unifi consoles use self-signed certificates, so certificate validation
     * is deliberately skipped — same trust model as the mpv playback path
     * (FFmpeg does not verify RTSPS certs either). This socket only ever
     * carries analysis audio on the LAN; no credentials flow through it.
     */
    @SuppressLint("CustomX509TrustManager", "TrustAllX509TrustManager")
    private fun trustAllSslSocketFactory(): SSLSocketFactory {
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) = Unit
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) = Unit
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })
        val sslContext = SSLContext.getInstance("TLS")
        sslContext.init(null, trustAll, SecureRandom())
        return sslContext.socketFactory
    }

    private companion object {
        const val TAG = "LevelMeter"
        const val INITIAL_BACKOFF_MS = 2_000L
        const val MAX_BACKOFF_MS = 60_000L
        const val SOCKET_TIMEOUT_MS = 10_000L
        const val STALL_CHECK_INTERVAL_MS = 15_000L
        const val STALL_THRESHOLD_MS = 20_000L
    }
}
