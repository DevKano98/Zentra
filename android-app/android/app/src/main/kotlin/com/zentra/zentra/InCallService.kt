package com.zentra.zentra

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.telecom.Call
import android.telecom.InCallService
import android.content.Intent
import android.app.PendingIntent
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class InCallService : InCallService() {

    companion object {
        const val CHANNEL = "zentra/audio"
        const val SAMPLE_RATE_RECORD = 16000
        const val SAMPLE_RATE_PLAY = 22050
    }

    // Changed from private -> public so MainActivity can access it
    var currentCall: Call? = null

    private var audioRecord: AudioRecord? = null
    private var audioTrack: AudioTrack? = null
    private var isCapturing = false
    private var isScreeningCall = false  // Set by Flutter when AI screening is active
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        InCallServiceHolder.instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAudioCapture()
        isScreeningCall = false
        serviceScope.cancel()
        InCallServiceHolder.instance = null
    }

    private fun getChannel(): MethodChannel? {
        val engine = FlutterEngineCache.getInstance().get("main_engine") ?: return null
        return MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    }

    /// Called by Flutter when AI screening is being set up for this call
    fun startScreeningMode() {
        isScreeningCall = true
        // If call is already ringing, auto-answer it for AI screening
        currentCall?.let { call ->
            if (call.state == Call.STATE_RINGING) {
                call.answer(0)  // Answer silently; audio capture starts in STATE_ACTIVE callback
            }
        }
        
        // Android restriction: Cannot inject audio directly into cellular uplink.
        // Workaround: Turn on speakerphone so the device mic picks up the AI voice from the speaker.
        val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
        audioManager.isSpeakerphoneOn = true
        // Mute the actual uplink mic so user's background noise doesn't interfere
        // Wait, if we mute the mic, how does the speakerphone feedback work? 
        // Actually, if we mute the microphone via AudioManager, the caller hears NOTHING (not even the speaker output).
        // Let's NOT mute it, but rather just rely on speakerphone for acoustic coupling.
        // On some devices, CallAudioState handles this natively, but let's stick to speakerphone.
    }

    override fun onCallAdded(call: Call) {
        super.onCallAdded(call)
        currentCall = call
        InCallServiceHolder.instance?.currentCall = call

        call.registerCallback(object : Call.Callback() {
            override fun onStateChanged(call: Call, state: Int) {
                when (state) {
                    Call.STATE_RINGING, Call.STATE_DIALING, Call.STATE_CONNECTING -> {
                        val number = call.details.handle?.schemeSpecificPart ?: ""
                        launchMainActivity()
                        CoroutineScope(Dispatchers.Main).launch {
                            delay(500) // Give flutter a moment
                            getChannel()?.invokeMethod("callStarted", mapOf(
                                "number" to number,
                                "state" to state
                            ))
                        }
                    }
                    Call.STATE_ACTIVE -> {
                        getChannel()?.invokeMethod("callActive", null)
                        startAudioCapture()
                    }
                    Call.STATE_DISCONNECTED, Call.STATE_DISCONNECTING -> {
                        stopAudioCapture()
                        notifyCallEnded()
                    }
                }
            }
        })

        val initialState = call.state
        if (initialState == Call.STATE_RINGING || 
            initialState == Call.STATE_DIALING || 
            initialState == Call.STATE_CONNECTING) {
            val number = call.details.handle?.schemeSpecificPart ?: ""
            launchMainActivity()
            CoroutineScope(Dispatchers.Main).launch {
                delay(500) 
                getChannel()?.invokeMethod("callStarted", mapOf(
                    "number" to number,
                    "state" to initialState
                ))
            }
        }
    }

    private fun launchMainActivity() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        }
        startActivity(intent)
    }

    override fun onCallRemoved(call: Call) {
        super.onCallRemoved(call)
        stopAudioCapture()
        notifyCallEnded()
        currentCall = null
        isScreeningCall = false
    }

    private fun startAudioCapture() {
        if (isCapturing) return
        isCapturing = true

        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE_RECORD,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val bufferSize = maxOf(minBufferSize, SAMPLE_RATE_RECORD / 10 * 2)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE_RECORD,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )

        audioRecord?.startRecording()

        serviceScope.launch {
            val buffer = ByteArray(bufferSize)

            while (isCapturing && audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0

                if (read > 0) {
                    val chunk = buffer.copyOf(read)

                    withContext(Dispatchers.Main) {
                        getChannel()?.invokeMethod("audioChunk", mapOf("data" to chunk))
                    }
                }
            }
        }
    }

    private fun stopAudioCapture() {
        isCapturing = false

        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null

        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        
        // Turn off speakerphone when call ends or screening is over
        try {
            val audioManager = getSystemService(android.content.Context.AUDIO_SERVICE) as android.media.AudioManager
            audioManager.isSpeakerphoneOn = false
        } catch (e: Exception) {}
    }

    private fun notifyCallEnded() {
        CoroutineScope(Dispatchers.Main).launch {
            getChannel()?.invokeMethod("callEnded", null)
        }
    }

    fun playAudioBytes(audioBytes: ByteArray) {
        serviceScope.launch {
            // Sarvam TTS returns WAV with 44-byte header; AudioTrack needs raw PCM
            val pcmBytes = if (audioBytes.size > 44 &&
                audioBytes[0] == 'R'.code.toByte() &&
                audioBytes[1] == 'I'.code.toByte() &&
                audioBytes[2] == 'F'.code.toByte() &&
                audioBytes[3] == 'F'.code.toByte()) {
                audioBytes.copyOfRange(44, audioBytes.size)
            } else {
                audioBytes
            }

            if (pcmBytes.isEmpty()) return@launch

            val minBufferSize = AudioTrack.getMinBufferSize(
                SAMPLE_RATE_PLAY,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val bufferSize = maxOf(minBufferSize, pcmBytes.size)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA) // Use MEDIA to play through speaker reliably
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setSampleRate(SAMPLE_RATE_PLAY)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            track.write(pcmBytes, 0, pcmBytes.size)
            track.play()

            // Duration = bytes / (sampleRate * 2 bytes per sample) * 1000ms + buffer
            val durationMs = (pcmBytes.size.toLong() * 1000L) / (SAMPLE_RATE_PLAY * 2).toLong() + 300L
            delay(durationMs)

            track.stop()
            track.release()
        }
    }
}