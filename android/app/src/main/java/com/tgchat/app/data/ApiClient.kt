package com.tgchat.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

class ApiException(
    message: String,
    val code: String = "error",
    val status: Int = 0,
) : Exception(message)

class ApiClient(baseUrl: String) {

    var baseUrl: String = normalize(baseUrl)
    var token: String? = null

    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; isLenient = true }
    private val media = "application/json; charset=utf-8".toMediaType()
    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    companion object {
        fun normalize(raw: String): String {
            var u = raw.trim()
            if (u.isEmpty()) return u
            if (!u.startsWith("http://", true) && !u.startsWith("https://", true)) u = "https://$u"
            return u.trimEnd('/')
        }
    }

    private fun jsonBody(vararg pairs: Pair<String, Any?>): String = buildJsonObject {
        for ((key, value) in pairs) {
            when (value) {
                null -> put(key, JsonNull)
                is String -> put(key, value)
                is Int -> put(key, value)
                is Long -> put(key, value)
                is Boolean -> put(key, value)
                is List<*> -> put(key, buildJsonArray {
                    for (item in value) if (item is String) add(item)
                })
                else -> put(key, value.toString())
            }
        }
    }.toString()

    private suspend fun raw(method: String, path: String, payload: String?, auth: Boolean): String {
        val url = baseUrl.trimEnd('/') + path
        val builder = Request.Builder().url(url).header("Accept", "application/json")
        if (payload != null) {
            builder.method(method, payload.toRequestBody(media))
        } else if (method != "GET") {
            builder.method(method, "".toRequestBody(media))
        } else {
            builder.method("GET", null)
        }
        if (auth) token?.let { builder.header("Authorization", "Bearer $it") }

        val response = withContext(Dispatchers.IO) {
            try {
                http.newCall(builder.build()).execute()
            } catch (e: IOException) {
                throw ApiException("无法连接服务器，请检查网络或服务器地址", "network")
            }
        }

        response.use { resp ->
            val text = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                val parsed = try {
                    json.decodeFromString(ErrorResponse.serializer(), text)
                } catch (_: Exception) {
                    null
                }
                throw ApiException(
                    parsed?.error ?: "请求失败（HTTP ${resp.code}）",
                    parsed?.code ?: "http_${resp.code}",
                    resp.code,
                )
            }
            return text
        }
    }

    private suspend inline fun <reified T> request(
        method: String,
        path: String,
        payload: String? = null,
        auth: Boolean = true,
    ): T {
        val text = raw(method, path, payload, auth)
        return json.decodeFromString(text)
    }

    suspend fun login(username: String, password: String): LoginResponse =
        request("POST", "/api/auth/login", jsonBody("username" to username, "password" to password), auth = false)

    suspend fun logout() {
        try {
            raw("POST", "/api/auth/logout", null, auth = true)
        } catch (_: Exception) {
            // best effort
        }
    }

    suspend fun me(): MeResponse = request("GET", "/api/me")

    suspend fun chats(): ChatsResponse = request("GET", "/api/chats")

    suspend fun messages(chatId: String, before: Long = 0, limit: Int = 60): MessagesResponse =
        request("GET", "/api/chats/$chatId/messages?before=$before&limit=$limit")

    suspend fun sendMessage(chatId: String, text: String, clientId: String): MessageResponse =
        request("POST", "/api/chats/$chatId/messages", jsonBody("text" to text, "clientId" to clientId))

    suspend fun markRead(chatId: String, seq: Long) {
        try {
            raw("POST", "/api/chats/$chatId/read", jsonBody("seq" to seq), auth = true)
        } catch (_: Exception) {
            // best effort
        }
    }

    suspend fun users(query: String = ""): UsersResponse =
        request("GET", "/api/users?query=" + URLEncoder.encode(query, "UTF-8"))

    suspend fun createChat(memberIds: List<String>, title: String? = null): ChatResponse =
        request("POST", "/api/chats", jsonBody("memberIds" to memberIds, "title" to title))

    suspend fun updateMe(displayName: String?, avatarColor: String?): MeResponse =
        request("PATCH", "/api/me", jsonBody("displayName" to displayName, "avatarColor" to avatarColor))

    suspend fun adminUsers(): UsersResponse = request("GET", "/api/admin/users")

    suspend fun adminCreateUser(
        username: String,
        password: String,
        displayName: String?,
        role: String,
    ): CreateUserResponse = request(
        "POST",
        "/api/admin/users",
        jsonBody("username" to username, "password" to password, "displayName" to displayName, "role" to role),
    )

    suspend fun adminResetPassword(userId: String, password: String) {
        raw("POST", "/api/admin/users/$userId/reset-password", jsonBody("password" to password), auth = true)
    }
}
