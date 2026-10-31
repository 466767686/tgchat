package com.tgchat.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
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

    suspend fun messages(
        chatId: String,
        before: Long = 0,
        limit: Int = 60,
        topicId: String? = null,
    ): MessagesResponse {
        var path = "/api/chats/$chatId/messages?before=$before&limit=$limit"
        if (!topicId.isNullOrEmpty()) path += "&topic=${URLEncoder.encode(topicId, "UTF-8")}"
        return request("GET", path)
    }

    suspend fun sendMessage(
        chatId: String,
        text: String,
        clientId: String,
        mediaId: String? = null,
        replyTo: Long? = null,
        topicId: String? = null,
        forwardedFrom: String? = null,
    ): MessageResponse = request(
        "POST",
        "/api/chats/$chatId/messages",
        body {
            put("text", text)
            put("clientId", clientId)
            mediaId?.let { put("mediaId", it) }
            replyTo?.let { put("replyTo", it) }
            topicId?.let { put("topicId", it) }
            forwardedFrom?.let { put("forwardedFrom", it) }
        },
    )

    suspend fun editMessage(chatId: String, seq: Long, text: String): MessageResponse =
        request("PATCH", "/api/chats/$chatId/messages/$seq", body { put("text", text) })

    suspend fun deleteMessage(chatId: String, seq: Long) {
        raw("DELETE", "/api/chats/$chatId/messages/$seq", null, auth = true)
    }

    suspend fun toggleReaction(chatId: String, seq: Long, emoji: String): ReactionsResponse =
        request("POST", "/api/chats/$chatId/messages/$seq/reactions", body { put("emoji", emoji) })

    suspend fun pinMessage(chatId: String, seq: Long, pinned: Boolean) {
        raw("POST", "/api/chats/$chatId/pin", body { put("seq", seq); put("pinned", pinned) }, auth = true)
    }

    suspend fun searchMessages(chatId: String, query: String): MessagesResponse =
        request("GET", "/api/chats/$chatId/search?q=" + URLEncoder.encode(query, "UTF-8"))

    fun mediaUrl(media: MediaDto): String {
        val path = if (media.url.startsWith("http")) media.url else baseUrl.trimEnd('/') + media.url
        val tok = token ?: return path
        return if (path.contains("?")) "$path&token=$tok" else "$path?token=$tok"
    }

    suspend fun uploadMedia(
        chatId: String,
        bytes: ByteArray,
        fileName: String,
        mimeType: String,
        kind: String,
        width: Int? = null,
        height: Int? = null,
        durationMs: Int? = null,
        onProgress: ((Float) -> Unit)? = null,
    ): MediaResponse {
        val url = baseUrl.trimEnd('/') + "/api/chats/$chatId/media"
        val fileBody = bytes.toRequestBody(mimeType.toMediaType())
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
            .addFormDataPart("file", fileName, fileBody)
            .addFormDataPart("kind", kind)
            .addFormDataPart("name", fileName)
        width?.let { builder.addFormDataPart("width", it.toString()) }
        height?.let { builder.addFormDataPart("height", it.toString()) }
        durationMs?.let { builder.addFormDataPart("durationMs", it.toString()) }
        val requestBuilder = Request.Builder().url(url).post(builder.build())
        token?.let { requestBuilder.header("Authorization", "Bearer $it") }
        val respText = withContext(Dispatchers.IO) {
            try {
                http.newCall(requestBuilder.build()).execute().use { resp ->
                    val text = resp.body?.string().orEmpty()
                    if (!resp.isSuccessful) {
                        throw ApiException(
                            try { json.decodeFromString(ErrorResponse.serializer(), text).error ?: "上传失败" }
                            catch (_: Exception) { "上传失败（HTTP ${resp.code}）" },
                            "upload_failed",
                            resp.code,
                        )
                    }
                    text
                }
            } catch (e: IOException) {
                throw ApiException("网络错误，上传失败", "network")
            }
        }
        onProgress?.invoke(1f)
        return json.decodeFromString(respText)
    }

    suspend fun downloadMedia(media: MediaDto): ByteArray = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(mediaUrl(media))
        try {
            http.newCall(builder.build()).execute().use { resp ->
                if (!resp.isSuccessful) throw ApiException("下载失败", "download_failed", resp.code)
                resp.body?.bytes() ?: throw ApiException("下载失败", "download_failed")
            }
        } catch (e: IOException) {
            throw ApiException("网络错误，下载失败", "network")
        }
    }

    suspend fun createGroup(title: String, memberIds: List<String>, description: String = ""): ChatResponse =
        request(
            "POST",
            "/api/chats",
            body {
                put("type", "group")
                put("title", title)
                put("description", description)
                put("memberIds", buildJsonArray { memberIds.forEach { add(it) } })
            },
        )

    suspend fun updateChat(chatId: String, fields: Map<String, Any?>): ChatResponse = request(
        "PATCH",
        "/api/chats/$chatId",
        buildJsonObject {
            fields.forEach { (key, value) ->
                when (value) {
                    null -> put(key, JsonNull)
                    is String -> put(key, value)
                    is Int -> put(key, value)
                    is Long -> put(key, value)
                    is Boolean -> put(key, value)
                    else -> put(key, value.toString())
                }
            }
        }.toString(),
    )

    suspend fun addMember(chatId: String, userId: String): ChatResponse =
        request("POST", "/api/chats/$chatId/members", body { put("userId", userId) })

    suspend fun removeMember(chatId: String, userId: String) {
        raw("DELETE", "/api/chats/$chatId/members/$userId", null, auth = true)
    }

    suspend fun setMemberRole(chatId: String, userId: String, role: String): ChatResponse =
        request("PATCH", "/api/chats/$chatId/members/$userId", body { put("role", role) })

    suspend fun muteMember(chatId: String, userId: String, until: Long): ChatResponse =
        request("PATCH", "/api/chats/$chatId/members/$userId", body { put("mutedUntil", until) })

    suspend fun createInvite(chatId: String): InviteResponse =
        request("POST", "/api/chats/$chatId/invite", body { put("expiresInDays", 0) })

    suspend fun leaveChat(chatId: String) {
        raw("POST", "/api/chats/$chatId/leave", null, auth = true)
    }

    suspend fun dissolveChat(chatId: String) {
        raw("DELETE", "/api/chats/$chatId", null, auth = true)
    }

    suspend fun joinByCode(code: String): ChatResponse =
        request("POST", "/api/chats/join", body { put("code", code) })

    suspend fun batchChats(action: String, chatIds: List<String>): SimpleResponse = request(
        "POST",
        "/api/chats/batch",
        body {
            put("action", action)
            put("chatIds", buildJsonArray { chatIds.forEach { add(it) } })
        },
    )

    suspend fun folders(): FoldersResponse = request("GET", "/api/folders")

    suspend fun createFolder(name: String): FolderResponse =
        request("POST", "/api/folders", body { put("name", name) })

    suspend fun deleteFolder(id: String) {
        raw("DELETE", "/api/folders/$id", null, auth = true)
    }

    suspend fun assignFolder(chatId: String, folderId: String?) {
        raw("PATCH", "/api/chats/$chatId/folder", body { folderId?.let { put("folderId", it) } ?: put("folderId", JsonNull) }, auth = true)
    }

    suspend fun setWallpaper(chatId: String, wallpaper: String?) {
        raw("POST", "/api/chats/$chatId/wallpaper", body { wallpaper?.let { put("wallpaper", it) } ?: put("wallpaper", JsonNull) }, auth = true)
    }

    suspend fun savedChat(): ChatResponse = request("POST", "/api/saved", null)

    suspend fun globalSearch(query: String, kind: String = ""): MessagesResponse {
        var path = "/api/search?q=" + URLEncoder.encode(query, "UTF-8")
        if (kind.isNotEmpty()) path += "&kind=$kind"
        return request("GET", path)
    }

    suspend fun createChannel(title: String, username: String?, description: String): ChatResponse = request(
        "POST",
        "/api/channels",
        body {
            put("title", title)
            put("description", description)
            username?.takeIf { it.isNotEmpty() }?.let { put("username", it) }
        },
    )

    suspend fun discoverChannels(query: String): ChannelsResponse =
        request("GET", "/api/channels/discover?q=" + URLEncoder.encode(query, "UTF-8"))

    suspend fun subscribe(chatId: String): ChatResponse = request("POST", "/api/chats/$chatId/subscribe", null)

    suspend fun unsubscribe(chatId: String) {
        raw("DELETE", "/api/chats/$chatId/subscribe", null, auth = true)
    }

    suspend fun updateProfile(fields: Map<String, Any?>): UserResponse = request(
        "PATCH",
        "/api/me",
        buildJsonObject {
            fields.forEach { (key, value) ->
                when (value) {
                    null -> put(key, JsonNull)
                    is String -> put(key, value)
                    is Boolean -> put(key, value)
                    is Int -> put(key, value)
                    else -> put(key, value.toString())
                }
            }
        }.toString(),
    )

    suspend fun sessions(): SessionsResponse = request("GET", "/api/sessions")

    suspend fun revokeSession(id: String) {
        raw("DELETE", "/api/sessions/$id", null, auth = true)
    }

    suspend fun revokeOtherSessions() {
        raw("DELETE", "/api/sessions", null, auth = true)
    }

    suspend fun blocks(): UsersResponse = request("GET", "/api/blocks")

    suspend fun setBlock(userId: String, blocked: Boolean) {
        raw(if (blocked) "POST" else "DELETE", "/api/users/$userId/block", null, auth = true)
    }

    private fun body(build: JsonObjectBuilder.() -> Unit): String = buildJsonObject(build).toString()

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
