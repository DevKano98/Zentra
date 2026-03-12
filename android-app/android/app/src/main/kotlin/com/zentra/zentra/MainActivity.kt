package com.zentra.zentra

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
package com.zentra

import android.content.Intent
import android.telecom.TelecomManager
import android.app.role.RoleManager
import android.os.Build
import android.os.Bundle
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
        const val CHANNEL_SETUP = "zentra/setup"
        const val REQUEST_CODE_DEFAULT_DIALER = 1001
    }

    private lateinit var screeningChannel: MethodChannel
    private lateinit var audioChannel: MethodChannel
    private lateinit var callChannel: MethodChannel
    private lateinit var notificationsChannel: MethodChannel
    private lateinit var setupChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache engine for use by services
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // 1. Screening channel
        screeningChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SCREENING)
        screeningChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "endCall" -> {
                    // Flutter requesting call end
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
                        // Forward to InCallService
                        InCallServiceHolder.instance?.playAudioBytes(audioBytes)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "No audio bytes provided", null)
                    }
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
        setupChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_SETUP)
        setupChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDefaultDialer" -> {
                    requestDefaultDialer()
                    result.success(null)
                }
                "isDefaultDialer" -> {
                    val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
                    result.success(telecomManager.defaultDialerPackage == packageName)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requestDefaultDialer() {
        val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
        if (telecomManager.defaultDialerPackage != packageName) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val roleManager = getSystemService(RoleManager::class.java)
                if (roleManager.isRoleAvailable(RoleManager.ROLE_DIALER) &&
                    !roleManager.isRoleHeld(RoleManager.ROLE_DIALER)) {
                    val intent = roleManager.createRequestRoleIntent(RoleManager.ROLE_DIALER)
                    startActivityForResult(intent, REQUEST_CODE_DEFAULT_DIALER)
                }
            } else {
                @Suppress("DEPRECATION")
                val intent = Intent(TelecomManager.ACTION_CHANGE_DEFAULT_DIALER)
                    .putExtra(
                        TelecomManager.EXTRA_CHANGE_DEFAULT_DIALER_PACKAGE_NAME,
                        packageName
                    )
                startActivity(intent)
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
        if (requestCode == REQUEST_CODE_DEFAULT_DIALER) {
            val telecomManager = getSystemService(TELECOM_SERVICE) as TelecomManager
            val isDefault = telecomManager.defaultDialerPackage == packageName
            setupChannel.invokeMethod("defaultDialerResult", mapOf("isDefault" to isDefault))
        }
    }
}

// Singleton holder for InCallService access from MainActivity
object InCallServiceHolder {
    var instance: InCallService? = null
}