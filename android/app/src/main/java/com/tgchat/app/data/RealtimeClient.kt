package com.tgchat.app.data

import android.util.Log
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
 * WebSocket transport for one conversation at a time.
 * The server pushes new messages, typing indicators and read receipts.
 */
class RealtimeClient {

    interface Listener {
        fun onOpen()
        fun onMessage(message: MessageDto)
        fun onTyping(userId: String, name: String)
        fun onRead(userId: String, seq: Long)
        fun onClosed()
        fun onEdit(message: MessageDto) {}
        fun onDelete(seq: Long) {}
        fun onReaction(seq: Long, reactions: List<ReactionDto>) {}
        fun onPin(seq: Long, pinned: Boolean) {}
        fun onPoll(seq: Long, poll: PollDto) {}
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val http = OkHttpClient.Builder()
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    @Volatile private var disposed = true

    fun connect(baseUrl: String, chatId: String, token: String, listener: Listener): Boolean {
        disconnect()
        val wsBase = when {
            baseUrl.startsWith("https://") -> "wss://" + baseUrl.removePrefix("https://")
            baseUrl.startsWith("http://") -> "ws://" + baseUrl.removePrefix("http://")
            else -> "wss://$baseUrl"
        }
        val url = "$wsBase/api/ws?chat=$chatId&token=$token"
        val request = try {
            Request.Builder().url(url).build()
        } catch (e: Exception) {
            Log.w(TAG, "bad ws url: $url")
            return false
        }
        disposed = false
        socket = http.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                if (!disposed) listener.onOpen()
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                handle(text, listener)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                if (!disposed) {
                    disposed = true
                    listener.onClosed()
                }
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (!disposed) {
                    disposed = true
                    listener.onClosed()
                }
            }
        })
        return true
    }

    private fun handle(text: String, listener: Listener) {
        try {
            val obj = json.parseToJsonElement(text).jsonObject
            when (obj["type"]?.jsonPrimitive?.content) {
                "message" -> obj["message"]?.let {
                    listener.onMessage(json.decodeFromJsonElement(MessageDto.serializer(), it))
                }
                "typing" -> listener.onTyping(
                    obj["userId"]?.jsonPrimitive?.content ?: "",
                    obj["name"]?.jsonPrimitive?.content ?: "",
                )
                "read" -> listener.onRead(
                    obj["userId"]?.jsonPrimitive?.content ?: "",
                    obj["seq"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                )
                "edit" -> obj["message"]?.let {
                    listener.onEdit(json.decodeFromJsonElement(MessageDto.serializer(), it))
                }
                "delete" -> listener.onDelete(
                    obj["seq"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                )
                "reaction" -> listener.onReaction(
                    obj["seq"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                    obj["reactions"]?.let {
                        json.decodeFromJsonElement(
                            kotlinx.serialization.builtins.ListSerializer(ReactionDto.serializer()),
                            it,
                        )
                    } ?: emptyList(),
                )
                "pin" -> listener.onPin(
                    obj["seq"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L,
                    obj["pinned"]?.jsonPrimitive?.content?.toBoolean() ?: false,
                )
                "poll" -> obj["poll"]?.let { payload ->
                    val seq = obj["seq"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0L
                    listener.onPoll(seq, json.decodeFromJsonElement(PollDto.serializer(), payload))
                }
                else -> Unit
            }
        } catch (e: Exception) {
            Log.w(TAG, "unparseable event: $text")
        }
    }

    fun sendTyping() {
        try {
            socket?.send("{\"type\":\"typing\"}")
        } catch (_: Exception) {
            // socket is gone; polling will keep the screen fresh
        }
    }

    fun disconnect() {
        disposed = true
        try {
            socket?.close(1000, "bye")
        } catch (_: Exception) {
            // ignore
        }
        socket = null
    }

    private companion object {
        const val TAG = "Realtime"
    }
}
