package com.tgchat.app.push

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restarts the background connection after a reboot. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val credentials = RealtimeService.savedCredentials(context) ?: return
        runCatching { RealtimeService.start(context, credentials.first, credentials.second) }
    }
}
