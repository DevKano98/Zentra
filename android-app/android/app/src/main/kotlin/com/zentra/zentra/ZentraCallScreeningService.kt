package com.zentra.zentra

import android.content.Intent
import android.net.Uri
import android.provider.ContactsContract
import android.telecom.Call
import android.telecom.CallScreeningService
import android.telecom.CallScreeningService.CallResponse

class ZentraCallScreeningService : CallScreeningService() {

    override fun onScreenCall(callDetails: Call.Details) {
        val callerNumber = callDetails.handle?.schemeSpecificPart ?: ""
        
        // Always allow emergency numbers
        val emergencyNumbers = listOf("112", "100", "101", "102", "108")
        if (emergencyNumbers.any { callerNumber.contains(it) }) {
            respondToCall(callDetails, buildAllowResponse())
            return
        }
        
        // Always allow known contacts
        if (isNumberInContacts(callerNumber)) {
            respondToCall(callDetails, buildAllowResponse())
            return
        }
        
        // Unknown number — silence ring, start AI screening
        // IMPORTANT: setDisallowCall(false) keeps call alive
        // setSilenceCall(true) just stops ringing
        respondToCall(callDetails, buildSilenceResponse())
        
        // Notify Flutter to show screening screen
        val intent = Intent(this, MainActivity::class.java).apply {
            action = "START_AI_SCREENING"
            putExtra("caller_number", callerNumber)
            putExtra("call_id", System.currentTimeMillis().toString())
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP) // Ensure it brings to front reliably
        }
        startActivity(intent)
    }
    
    private fun buildAllowResponse(): CallResponse {
        return CallResponse.Builder()
            .setDisallowCall(false)
            .setSkipCallLog(false)
            .build()
    }
    
    private fun buildSilenceResponse(): CallResponse {
        return CallResponse.Builder()
            .setDisallowCall(false)
            .setSkipCallLog(false)
            .setSilenceCall(true)
            .build()
    }
    
    private fun isNumberInContacts(number: String): Boolean {
        if (number.isEmpty()) return false
        return try {
            val uri = Uri.withAppendedPath(
                ContactsContract.PhoneLookup.CONTENT_FILTER_URI,
                Uri.encode(number)
            )
            val cursor = contentResolver.query(
                uri,
                arrayOf(ContactsContract.PhoneLookup.DISPLAY_NAME),
                null, null, null
            )
            val found = (cursor?.count ?: 0) > 0
            cursor?.close()
            found
        } catch (e: Exception) {
            false  // If contacts check fails, treat as unknown
        }
    }
}
