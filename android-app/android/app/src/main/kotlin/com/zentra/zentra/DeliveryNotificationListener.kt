package com.zentra.zentra

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

class DeliveryNotificationListener : NotificationListenerService() {

    companion object {
        const val CHANNEL = "zentra/notifications"

        val WATCHED_PACKAGES = setOf(
            "com.application.zomato",
            "in.swiggy.android",
            "com.amazon.mShop.android.shopping",
            "com.flipkart.android"
        )
    }

    private fun getChannel(): MethodChannel? {
        val engine = FlutterEngineCache.getInstance().get("main_engine") ?: return null
        return MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName !in WATCHED_PACKAGES) return

        val notification = sbn.notification ?: return
        val extras = notification.extras

        val title = extras.getString(android.app.Notification.EXTRA_TITLE) ?: ""
        val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(android.app.Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        val fullText = if (bigText.isNotEmpty()) bigText else text

        CoroutineScope(Dispatchers.Main).launch {
            getChannel()?.invokeMethod(
                "deliveryNotification",
                mapOf(
                    "package" to sbn.packageName,
                    "title" to title,
                    "text" to fullText,
                    "timestamp" to sbn.postTime
                )
            )
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        // Optionally track dismissed notifications
    }
}