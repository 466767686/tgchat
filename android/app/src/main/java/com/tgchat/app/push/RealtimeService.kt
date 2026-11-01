package com.tgchat.app.push

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.content.ContextCompat
import com.tgchat.app.data.MessageDto
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/**
 * Keeps one user-level WebSocket open while the app is in the background and
 * turns incoming messages into system notifications.
 */
class RealtimeService : Service() {

    companion object {
        private const val PREFS = "tgchat_service"
        private const val KEY_BASE = "base"
        private const val KEY_TOKEN = "token"

        fun start(context: Context, baseUrl: String, token: String) {
            val intent = Intent(context, RealtimeService::class.java)
                .putExtra(KEY_BASE, baseUrl)
                .putExtra(KEY_TOKEN, token)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RealtimeService::class.java))
        }

        /** Logout: stop the service and forget the saved credentials. */
        fun stopAndClear(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
            stop(context)
        }

        fun savedCredentials(context: Context): Pair<String, String>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val base = prefs.getString(KEY_BASE, null)
            val token = prefs.getString(KEY_TOKEN, null)
            return if (!base.isNullOrBlank() && !token.isNullOrBlank()) base to token else null
        }
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val client = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .build()
    private val handler = Handler(Looper.getMainLooper())

    private var socket: WebSocket? = null
    private var stopped = false
    private var currentBase: String? = null
    private var currentToken: String? = null
    private val reconnectTask = Runnable { connect() }

    override fun onCreate() {
        super.onCreate()
        Notifications.ensureChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(Notifications.serviceId(), Notifications.serviceNotification(this))

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        val base = intent?.getStringExtra(KEY_BASE) ?: prefs.getString(KEY_BASE, null)
        val token = intent?.getStringExtra(KEY_TOKEN) ?: prefs.getString(KEY_TOKEN, null)

        if (base.isNullOrBlank() || token.isNullOrBlank()) {
            stopSelf()
            return START_NOT_STICKY
        }

        prefs.edit().putString(KEY_BASE, base).putString(KEY_TOKEN, token).apply()

        if (base != currentBase || token != currentToken || socket == null) {
            currentBase = base
            currentToken = token
            connect()
        }
        return START_STICKY
    }

    private fun connect() {
        if (stopped) return
        val base = currentBase ?: return
        val token = currentToken ?: return

        runCatching { socket?.cancel() }
        socket = null

        val wsBase = base.trimEnd('/')
            .replaceFirst("https://", "wss://")
            .replaceFirst("http://", "ws://")
        val url = "$wsBase/api/ws?user=1&token=$token"

        val request = runCatching { Request.Builder().url(url).build() }.getOrNull() ?: return
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onMessage(webSocket: WebSocket, text: String) {
                handle(text)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                scheduleReconnect()
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                scheduleReconnect()
            }
        })
    }

    private fun scheduleReconnect() {
        if (stopped) return
        handler.removeCallbacks(reconnectTask)
        handler.postDelayed(reconnectTask, 5_000)
    }

    private fun handle(text: String) {
        val root = runCatching { json.parseToJsonElement(text).jsonObject }.getOrNull() ?: return
        if (root["type"]?.jsonPrimitive?.content != "message") return
        val payload = root["message"] ?: return
        val message = runCatching {
            json.decodeFromJsonElement(MessageDto.serializer(), payload)
        }.getOrNull() ?: return

        if (AppVisibility.visible) {
            IncomingCenter.publish(message)
            return
        }
        Notifications.showMessage(this, message)
    }

    override fun onDestroy() {
        stopped = true
        handler.removeCallbacksAndMessages(null)
        runCatching { socket?.close(1000, "bye") }
        socket = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
