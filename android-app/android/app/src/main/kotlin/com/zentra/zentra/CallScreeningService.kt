package com.zentra

import android.telecom.Call
import android.telecom.CallScreeningService
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class CallScreeningService : CallScreeningService() {

    companion object {
        const val CHANNEL = "zentra/screening"
    }

    private val emergencyNumbers = listOf("112", "100", "101", "102", "108")

    private fun isEmergencyNumber(number: String): Boolean {
        return number.trim() in emergencyNumbers
    }

    private fun checkIfInContacts(phoneNumber: String): Boolean {
        val uri = Uri.withAppendedPath(
            ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
            Uri.encode(phoneNumber)
        )
        val cursor = contentResolver.query(
            uri,
            arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
            null, null, null
        )
        val found = (cursor?.count ?: 0) > 0
        cursor?.close()
        return found
    }

    override fun onScreenCall(callDetails: Call.Details) {
        val number = callDetails.handle?.schemeSpecificPart ?: ""

        // Always allow emergency numbers through
        if (isEmergencyNumber(number)) {
            val response = CallResponse.Builder().build()
            respondToCall(callDetails, response)
            return
        }

        // Known contacts ring normally
        if (checkIfInContacts(number)) {
            val response = CallResponse.Builder().build()
            respondToCall(callDetails, response)
            return
        }

        // Unknown number — silence and let AI screen
        val response = CallResponse.Builder()
            .setSilenceCall(true)
            .build()
        respondToCall(callDetails, response)

        // Notify Flutter via cached engine
        val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("main_engine")
        engine?.let {
            val channel = MethodChannel(it.dartExecutor.binaryMessenger, CHANNEL)
            channel.invokeMethod(
                "incomingCall",
                mapOf("number" to number)
            )
        }
    }
}