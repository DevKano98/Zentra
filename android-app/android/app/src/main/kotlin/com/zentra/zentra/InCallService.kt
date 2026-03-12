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
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onCreate() {
        super.onCreate()
        InCallServiceHolder.instance = this
    }

    override fun onDestroy() {
        super.onDestroy()
        stopAudioCapture()
        serviceScope.cancel()
        InCallServiceHolder.instance = null
    }

    private fun getChannel(): MethodChannel? {
        val engine = FlutterEngineCache.getInstance().get("main_engine") ?: return null
        return MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
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
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
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
    }

    private fun notifyCallEnded() {
        CoroutineScope(Dispatchers.Main).launch {
            getChannel()?.invokeMethod("callEnded", null)
        }
    }

    fun playAudioBytes(audioBytes: ByteArray) {
        serviceScope.launch {

            val minBufferSize = AudioTrack.getMinBufferSize(
                SAMPLE_RATE_PLAY,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )

            val bufferSize = maxOf(minBufferSize, audioBytes.size)

            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
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

            track.write(audioBytes, 0, audioBytes.size)
            track.play()

            delay((audioBytes.size / (SAMPLE_RATE_PLAY * 2) * 1000L) + 200L)

            track.stop()
            track.release()
        }
    }
}