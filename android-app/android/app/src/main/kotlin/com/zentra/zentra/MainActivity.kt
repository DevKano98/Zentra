package com.zentra.zentra

import android.content.Intent
import android.telecom.TelecomManager
import android.app.role.RoleManager
import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.provider.CallLog
import android.provider.BlockedNumberContract
import android.content.ContentValues
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        const val CHANNEL_SCREENING = "zentra/screening"
        const val CHANNEL_AUDIO = "zentra/audio"
        const val CHANNEL_CALL = "zentra/call"
        const val CHANNEL_NOTIFICATIONS = "zentra/notifications"
        private const val REQUEST_CODE_SET_DEFAULT_DIALER = 1001
    }

    private lateinit var screeningChannel: MethodChannel
    private lateinit var audioChannel: MethodChannel
    private lateinit var callChannel: MethodChannel
    private lateinit var notificationsChannel: MethodChannel

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache engine for use by services
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // Handle initial intent if any
        handleIntent(intent)

        // 1. Screening channel
        screeningChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SCREENING)
        
        // Handle initial intent if any
        handleIntent(intent)

        screeningChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "endCall" -> {
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 2. Audio channel
        audioChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_AUDIO)
        audioChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "playAudioBytes" -> {
                    val audioBytes = call.argument<ByteArray>("data")
                    if (audioBytes != null) {
                        InCallServiceHolder.instance?.playAudioBytes(audioBytes)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "No audio bytes provided", null)
                    }
                }
                "startScreening" -> {
                    // Tell InCallService to auto-answer the call for AI screening
                    InCallServiceHolder.instance?.startScreeningMode()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 3. Call channel
        callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_CALL)
        callChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "endCurrentCall" -> {
                    InCallServiceHolder.instance?.currentCall?.disconnect()
                    result.success(null)
                }
                "answerCurrentCall" -> {
                    InCallServiceHolder.instance?.currentCall?.answer(0)
                    result.success(null)
                }
                "getCallState" -> {
                    val state = InCallServiceHolder.instance?.currentCall?.state ?: -1
                    result.success(state)
                }
                else -> result.notImplemented()
            }
        }

        // 4. Notifications channel
        notificationsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NOTIFICATIONS)
        notificationsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isNotificationListenerEnabled" -> {
                    val enabled = isNotificationListenerEnabled()
                    result.success(enabled)
                }
                "openNotificationListenerSettings" -> {
                    startActivity(Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // 5. Setup channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.zentra.dialer/call_control").setMethodCallHandler { call, result ->
            when (call.method) {
                "setDefaultDialer" -> {
                    val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
                    if (telecomManager.defaultDialerPackage != packageName) {
                        pendingResult = result
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(RoleManager::class.java)
                            val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                            startActivityForResult(intent, REQUEST_CODE_SET_DEFAULT_DIALER)
                        } else {
                            @Suppress("DEPRECATION")
                            val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                                .putExtra(TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME, packageName)
                            startActivityForResult(intent, REQUEST_CODE_SET_DEFAULT_DIALER)
                        }
                    } else {
                        result.success(true)
                    }
                }
                "checkDefaultDialer" -> {
                    val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
                    result.success(telecomManager.defaultDialerPackage == packageName)
                }
                "deleteCallLog" -> {
                    val number = call.argument<String>("number")
                    if (number != null) {
                        try {
                            val queryString = "${CallLog.Calls.NUMBER} = ?"
                            contentResolver.delete(CallLog.Calls.CONTENT_URI, queryString, arrayOf(number))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DELETE_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Number cannot be null", null)
                    }
                }
                "blockNumber" -> {
                    val number = call.argument<String>("number")
                    if (number != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        try {
                            val values = ContentValues().apply {
                                put(BlockedNumberContract.BlockedNumbers.COLUMN_ORIGINAL_NUMBER, number)
                            }
                            contentResolver.insert(BlockedNumberContract.BlockedNumbers.CONTENT_URI, values)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("BLOCK_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Number cannot be null or API too low", null)
                    }
                }
                "placeCall" -> {
                    val number = call.argument<String>("number")
                    if (number != null) {
                        try {
                            val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
                            val uri = Uri.fromParts("tel", number, null)
                            val extras = Bundle()
                            extras.putBoolean(TelecomManager.EXTRA_START_CALL_WITH_SPEAKERPHONE, false)
                            telecomManager.placeCall(uri, extras)
                            result.success(true)
                        } catch (e: SecurityException) {
                            result.error("SECURITY_EXCEPTION", "Missing CALL_PHONE permission", null)
                        } catch (e: Exception) {
                            result.error("CALL_FAILED", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Number cannot be null", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val listeners = android.provider.Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return listeners.contains(packageName)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SET_DEFAULT_DIALER) {
            val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
            val isDefault = telecomManager.defaultDialerPackage == packageName
            pendingResult?.success(isDefault)
            pendingResult = null
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == "START_AI_SCREENING") {
            val number = intent.getStringExtra("caller_number") ?: ""
            val callId = intent.getStringExtra("call_id") ?: ""
            
            // Give Flutter 500ms to mount MethodChannel listeners on cold start
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                // Notify Flutter via the main call control channel
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, "com.zentra.dialer/call_control")
                        .invokeMethod("incomingScreeningCall", mapOf(
                            "caller_number" to number,
                            "call_id" to callId
                        ))
                }
            }, 500)
        }
    }
}

object InCallServiceHolder {
    var instance: InCallService? = null
}