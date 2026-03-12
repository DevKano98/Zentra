package com.zentra.zentra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Services auto-restart as needed via Android Telecom framework
            // No explicit restart needed — CallScreeningService and InCallService
            // are system-bound and re-registered after reboot automatically
        }
    }
}