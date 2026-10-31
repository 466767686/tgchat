package com.tgchat.app

import android.app.Application
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.tgchat.app.data.ApiClient
import com.tgchat.app.data.ChatDto
import com.tgchat.app.data.MediaDto
import com.tgchat.app.data.MessageDto
import com.tgchat.app.data.PollDto
import com.tgchat.app.data.ReactionDto
import com.tgchat.app.data.ReplyPreviewDto
import com.tgchat.app.data.RealtimeClient
import com.tgchat.app.data.SessionStore
import com.tgchat.app.data.UserDto
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import java.util.UUID

enum class ThemeMode {
    SYSTEM, LIGHT, DARK;

    fun storageKey(): String = name.lowercase()

    companion object {
        fun from(value: String?): ThemeMode = when (value) {
            "light" -> LIGHT
            "dark" -> DARK
            else -> SYSTEM
        }
    }
}

sealed interface Route {
    data object Boot : Route
    data object Login : Route
    data object Chats : Route
    data class Chat(val id: String) : Route
    data object NewChat : Route
    data object Settings : Route
    data object Admin : Route
}

enum class MessageStatus { SENDING, SENT, FAILED }

data class UiMessage(
    val key: String,
    val seq: Long,
    val id: String,
    val clientId: String?,
    val senderId: String,
    val senderName: String,
    val senderColor: String,
    val text: String,
    val createdAt: Long,
    val status: MessageStatus = MessageStatus.SENT,
    val media: MediaDto? = null,
    val replyTo: ReplyPreviewDto? = null,
    val editedAt: Long? = null,
    val deleted: Boolean = false,
    val forwardedFrom: String? = null,
    val pinned: Boolean = false,
    val reactions: List<ReactionDto> = emptyList(),
    val poll: PollDto? = null,
    val views: Int? = null,
    val topicId: String? = null,
)

data class ChatUi(
    val id: String,
    val isGroup: Boolean,
    val title: String,
    val avatarColor: String,
    val peerId: String?,
    val lastText: String,
    val lastAt: Long,
    val lastFromMe: Boolean,
    val unread: Int,
    val otherReadSeq: Long,
    val members: List<UserDto>,
    val type: String = "direct",
    val pinned: Boolean = false,
    val archived: Boolean = false,
    val folderId: String? = null,
    val wallpaper: String? = null,
    val myRole: String? = null,
    val description: String? = null,
    val announcement: String? = null,
    val slowMode: Int = 0,
    val topicsEnabled: Boolean = false,
    val autoDeleteSeconds: Int = 0,
) {
    val isChannel: Boolean get() = type == "channel"
    val isSaved: Boolean get() = type == "saved"
    val canManage: Boolean get() = myRole == "owner" || myRole == "admin"
}

class AppViewModel(app: Application) : AndroidViewModel(app) {

    private val store = SessionStore(app)
    val api = ApiClient(BuildConfig.DEFAULT_BASE_URL)
    private val realtime = RealtimeClient()
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val scope = viewModelScope

    var themeMode by mutableStateOf(ThemeMode.SYSTEM)
        private set
    var disguiseEnabled by mutableStateOf(true)
        private set
    var unlockPin by mutableStateOf("1234")
        private set
    var locked by mutableStateOf(true)
        private set
    var baseUrl by mutableStateOf(ApiClient.normalize(BuildConfig.DEFAULT_BASE_URL))
        private set
    var token by mutableStateOf<String?>(null)
        private set
    var me by mutableStateOf<UserDto?>(null)
        private set
    var booting by mutableStateOf(true)
        private set
    var loginLoading by mutableStateOf(false)
        private set
    var loginError by mutableStateOf<String?>(null)
        private set
    var chats by mutableStateOf<List<ChatUi>>(emptyList())
        private set
    var chatsLoading by mutableStateOf(false)
        private set

    var activeChatId by mutableStateOf<String?>(null)
        private set
    var activeMessages by mutableStateOf<List<UiMessage>>(emptyList())
        private set
    var chatLoading by mutableStateOf(false)
        private set
    var loadingOlder by mutableStateOf(false)
        private set
    var typingUser by mutableStateOf<String?>(null)
        private set
    var hasMore by mutableStateOf<Map<String, Boolean>>(emptyMap())
        private set

    var usersDirectory by mutableStateOf<List<UserDto>>(emptyList())
        private set
    var usersLoading by mutableStateOf(false)
        private set

    var adminUsers by mutableStateOf<List<UserDto>>(emptyList())
        private set
    var adminBusy by mutableStateOf(false)
        private set
    var adminError by mutableStateOf<String?>(null)
        private set

    var toast by mutableStateOf<String?>(null)
        private set

    val backStack = mutableStateListOf<Route>(Route.Boot)
    val route: Route get() = backStack.last()

    private val messagesCache = mutableMapOf<String, List<UiMessage>>()
    private val lastReadSent = mutableMapOf<String, Long>()
    private var chatPollJob: Job? = null
    private var chatsPollJob: Job? = null
    private var typingJob: Job? = null
    private var loadJob: Job? = null
    private var lastTypingSentAt = 0L

    init {
        scope.launch {
            try {
                val stored = store.session.first()
                baseUrl = ApiClient.normalize(stored.baseUrl ?: BuildConfig.DEFAULT_BASE_URL)
                api.baseUrl = baseUrl
                themeMode = ThemeMode.from(stored.theme)
                disguiseEnabled = stored.disguise
                unlockPin = stored.unlockPin
                locked = disguiseEnabled

                val savedToken = stored.token
                if (!savedToken.isNullOrBlank()) {
                    token = savedToken
                    api.token = savedToken
                    val cached = stored.userJson?.let {
                        runCatching { json.decodeFromString(UserDto.serializer(), it) }.getOrNull()
                    }
                    me = cached
                    val online = runCatching { api.me().user }.getOrNull()
                    if (online != null) {
                        me = online
                        if (cached != null) store.saveSession(savedToken, json.encodeToString(UserDto.serializer(), online))
                    }
                    if (online != null || cached != null) {
                        backStack.clear()
                        backStack.add(Route.Chats)
                        refreshChats(silent = false)
                        startChatsPolling()
                    } else {
                        resetSession()
                    }
                } else {
                    backStack.clear()
                    backStack.add(Route.Login)
                }
            } catch (e: Exception) {
                backStack.clear()
                backStack.add(Route.Login)
            } finally {
                booting = false
            }
        }
    }

    // ------------------------------------------------------------------ auth

    fun login(username: String, password: String) {
        if (loginLoading) return
        if (username.isBlank() || password.isBlank()) {
            loginError = "请输入用户名和密码"
            return
        }
        loginLoading = true
        loginError = null
        scope.launch {
            try {
                val resp = api.login(username.trim(), password)
                token = resp.token
                api.token = resp.token
                me = resp.user
                store.saveSession(resp.token, json.encodeToString(UserDto.serializer(), resp.user))
                backStack.clear()
                backStack.add(Route.Chats)
                refreshChats(silent = false)
                startChatsPolling()
            } catch (e: Exception) {
                loginError = e.message ?: "登录失败"
            } finally {
                loginLoading = false
            }
        }
    }

    fun clearLoginError() {
        loginError = null
    }

    fun logout() {
        scope.launch {
            api.logout()
            realtime.disconnect()
            chatPollJob?.cancel()
            chatsPollJob?.cancel()
            store.clearSession()
            resetSession()
        }
    }

    private fun resetSession() {
        token = null
        api.token = null
        me = null
        chats = emptyList()
        messagesCache.clear()
        activeMessages = emptyList()
        activeChatId = null
        backStack.clear()
        backStack.add(Route.Login)
    }

    fun setBaseUrl(raw: String): Boolean {
        val normalized = ApiClient.normalize(raw)
        if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
            toast = "服务器地址无效"
            return false
        }
        baseUrl = normalized
        api.baseUrl = normalized
        scope.launch { store.saveBaseUrl(normalized) }
        return true
    }

    fun setTheme(mode: ThemeMode) {
        themeMode = mode
        scope.launch { store.saveTheme(mode.storageKey()) }
    }

    fun unlock() {
        locked = false
    }

    fun lock() {
        if (disguiseEnabled) locked = true
    }

    fun setDisguise(enabled: Boolean) {
        disguiseEnabled = enabled
        if (enabled) locked = true
        scope.launch { store.saveDisguise(enabled) }
    }

    fun changeUnlockPin(pin: String) {
        if (pin.length < 4) return
        unlockPin = pin
        scope.launch { store.saveUnlockPin(pin) }
    }

    fun clearToast() {
        toast = null
    }

    // ------------------------------------------------------------- navigation

    fun openChat(chatId: String) {
        val current = route
        if (current is Route.Chat && current.id == chatId) return
        if (current !is Route.Chat) backStack.add(Route.Chat(chatId))
        enterChat(chatId)
    }

    fun openNewChat() {
        backStack.add(Route.NewChat)
        loadUsers("")
    }

    fun openSettings() {
        backStack.add(Route.Settings)
    }

    fun openAdmin() {
        backStack.add(Route.Admin)
        loadAdminUsers()
    }

    fun back() {
        if (backStack.size <= 1) return
        backStack.removeAt(backStack.lastIndex)
        if (route !is Route.Chat) leaveChat()
    }

    fun goHome() {
        leaveChat()
        backStack.clear()
        backStack.add(Route.Chats)
    }

    private fun enterChat(chatId: String) {
        activeChatId = chatId
        typingUser = null
        activeMessages = messagesCache[chatId] ?: emptyList()
        chatLoading = activeMessages.isEmpty()
        chats = chats.map { if (it.id == chatId) it.copy(unread = 0) else it }
        loadMessages(chatId)
        connectRealtime(chatId)
        startChatPolling(chatId)
    }

    private fun leaveChat() {
        activeChatId = null
        activeMessages = emptyList()
        typingUser = null
        typingJob?.cancel()
        chatPollJob?.cancel()
        realtime.disconnect()
    }

    // ------------------------------------------------------------------ chats

    fun refreshChats(silent: Boolean = true) {
        if (token == null) return
        if (!silent) chatsLoading = true
        scope.launch {
            try {
                val resp = api.chats()
                chats = resp.chats.map { it.toChatUi(me?.id) }
            } catch (e: Exception) {
                if (!silent) toast = e.message
            } finally {
                if (!silent) chatsLoading = false
            }
        }
    }

    private fun startChatsPolling() {
        chatsPollJob?.cancel()
        chatsPollJob = scope.launch {
            while (isActive && token != null) {
                delay(5000)
                if (activeChatId == null) {
                    runCatching { api.chats() }.getOrNull()?.let { resp ->
                        chats = resp.chats.map { it.toChatUi(me?.id) }
                    }
                }
            }
        }
    }

    private fun startChatPolling(chatId: String) {
        chatPollJob?.cancel()
        chatPollJob = scope.launch {
            while (isActive && activeChatId == chatId) {
                delay(4000)
                runCatching { api.messages(chatId, 0, 40) }.getOrNull()?.let { resp ->
                    val merged = mergeMessages(messagesCache[chatId] ?: emptyList(), resp.messages.map { it.toUi() })
                    messagesCache[chatId] = merged
                    if (activeChatId == chatId) {
                        activeMessages = merged
                        latestServerSeq(merged)?.let { markRead(chatId, it) }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------- messages

    fun loadMessages(chatId: String, before: Long = 0) {
        loadJob?.cancel()
        loadJob = scope.launch {
            try {
                val resp = api.messages(chatId, before)
                val merged = mergeMessages(messagesCache[chatId] ?: emptyList(), resp.messages.map { it.toUi() })
                messagesCache[chatId] = merged
                if (activeChatId == chatId) {
                    activeMessages = merged
                    latestServerSeq(merged)?.let { markRead(chatId, it) }
                }
                hasMore = hasMore + (chatId to resp.hasMore)
                updateChatPreview(chatId, merged)
            } catch (e: Exception) {
                if (activeChatId == chatId && activeMessages.isEmpty()) toast = e.message
            } finally {
                if (activeChatId == chatId) chatLoading = false
            }
        }
    }

    fun loadOlder() {
        val chatId = activeChatId ?: return
        if (loadingOlder || hasMore[chatId] == false) return
        val oldest = messagesCache[chatId]?.firstOrNull { it.seq > 0 }?.seq ?: return
        loadingOlder = true
        scope.launch {
            try {
                val resp = api.messages(chatId, oldest)
                val merged = mergeMessages(messagesCache[chatId] ?: emptyList(), resp.messages.map { it.toUi() })
                messagesCache[chatId] = merged
                if (activeChatId == chatId) activeMessages = merged
                hasMore = hasMore + (chatId to resp.hasMore)
            } catch (_: Exception) {
                // keep the current window
            } finally {
                loadingOlder = false
            }
        }
    }

    fun sendMessage(text: String, replyTo: Long? = null) {
        val chatId = activeChatId ?: return
        val content = text.trim()
        if (content.isEmpty()) return
        val clientId = UUID.randomUUID().toString()
        val local = UiMessage(
            key = "c:$clientId",
            seq = 0,
            id = "local:$clientId",
            clientId = clientId,
            senderId = me?.id ?: "",
            senderName = me?.displayName ?: "",
            senderColor = me?.avatarColor ?: "#3390EC",
            text = content,
            createdAt = System.currentTimeMillis(),
            status = MessageStatus.SENDING,
            replyTo = replyTo?.let { seq ->
                messagesCache[chatId]?.firstOrNull { it.seq == seq }?.let {
                    ReplyPreviewDto(seq = seq, senderName = it.senderName, text = it.text)
                }
            },
        )
        val list = (messagesCache[chatId] ?: emptyList()) + local
        messagesCache[chatId] = list
        activeMessages = list

        scope.launch {
            try {
                val resp = api.sendMessage(chatId, content, clientId, replyTo = replyTo)
                applyIncoming(chatId, resp.message)
            } catch (e: Exception) {
                updateStatus(chatId, clientId, MessageStatus.FAILED)
                toast = e.message
            }
        }
    }

    fun retrySend(clientId: String) {
        val chatId = activeChatId ?: return
        val message = messagesCache[chatId]?.firstOrNull { it.clientId == clientId && it.seq == 0L } ?: return
        updateStatus(chatId, clientId, MessageStatus.SENDING)
        scope.launch {
            try {
                val resp = api.sendMessage(chatId, message.text, clientId)
                applyIncoming(chatId, resp.message)
            } catch (e: Exception) {
                updateStatus(chatId, clientId, MessageStatus.FAILED)
                toast = e.message
            }
        }
    }

    fun onComposerTyping(text: String) {
        if (text.isEmpty()) return
        val now = System.currentTimeMillis()
        if (now - lastTypingSentAt < 1500) return
        lastTypingSentAt = now
        realtime.sendTyping()
    }

    private fun applyIncoming(chatId: String, dto: MessageDto) {
        val merged = mergeMessages(messagesCache[chatId] ?: emptyList(), listOf(dto.toUi()))
        messagesCache[chatId] = merged
        if (activeChatId == chatId) {
            activeMessages = merged
            latestServerSeq(merged)?.let { markRead(chatId, it) }
        }
        updateChatPreview(chatId, merged)
    }

    private fun mergeMessages(existing: List<UiMessage>, incoming: List<UiMessage>): List<UiMessage> {
        val map = LinkedHashMap<String, UiMessage>()
        for (m in existing) map[m.key] = m
        for (m in incoming) {
            if (m.clientId != null) {
                val local = map.values.firstOrNull { it.clientId == m.clientId && it.seq == 0L }
                if (local != null) map.remove(local.key)
            }
            map[m.key] = m
        }
        return map.values.sortedWith(
            compareBy<UiMessage> { if (it.seq > 0) 0 else 1 }
                .thenBy { if (it.seq > 0) it.seq else it.createdAt },
        )
    }

    private fun latestServerSeq(messages: List<UiMessage>): Long? =
        messages.lastOrNull { it.seq > 0 }?.seq

    private fun updateStatus(chatId: String, clientId: String, status: MessageStatus) {
        val updated = (messagesCache[chatId] ?: emptyList()).map {
            if (it.clientId == clientId && it.seq == 0L) it.copy(status = status) else it
        }
        messagesCache[chatId] = updated
        if (activeChatId == chatId) activeMessages = updated
    }

    private fun updateChatPreview(chatId: String, messages: List<UiMessage>) {
        val last = messages.lastOrNull { it.seq > 0 } ?: return
        chats = chats.map { chat ->
            if (chat.id != chatId) chat
            else chat.copy(
                lastText = previewText(chat, last),
                lastAt = last.createdAt,
                lastFromMe = last.senderId == me?.id,
            )
        }
    }

    private fun previewText(chat: ChatUi, message: UiMessage): String = when {
        message.senderId == me?.id -> "你：${message.text}"
        chat.isGroup -> "${message.senderName}：${message.text}"
        else -> message.text
    }.replace("\n", " ")

    private fun markRead(chatId: String, seq: Long) {
        if (seq <= 0) return
        if ((lastReadSent[chatId] ?: 0L) >= seq) return
        lastReadSent[chatId] = seq
        chats = chats.map { if (it.id == chatId) it.copy(unread = 0) else it }
        scope.launch { api.markRead(chatId, seq) }
    }

    // --------------------------------------------------------------- realtime

    private fun connectRealtime(chatId: String) {
        val currentToken = token ?: return
        realtime.connect(
            baseUrl,
            chatId,
            currentToken,
            object : RealtimeClient.Listener {
                override fun onOpen() = Unit

                override fun onMessage(message: MessageDto) {
                    scope.launch {
                        if (activeChatId == chatId) applyIncoming(chatId, message)
                        else refreshChats(silent = true)
                    }
                }

                override fun onTyping(userId: String, name: String) {
                    scope.launch {
                        if (activeChatId == chatId && userId != me?.id) {
                            typingUser = name.ifBlank { "对方" }
                            typingJob?.cancel()
                            typingJob = scope.launch {
                                delay(3500)
                                typingUser = null
                            }
                        }
                    }
                }

                override fun onRead(userId: String, seq: Long) {
                    scope.launch {
                        if (userId != me?.id) {
                            chats = chats.map {
                                if (it.id == chatId) it.copy(otherReadSeq = maxOf(it.otherReadSeq, seq)) else it
                            }
                        }
                    }
                }

                override fun onEdit(message: MessageDto) {
                    scope.launch { applyIncoming(chatId, message) }
                }

                override fun onDelete(seq: Long) {
                    scope.launch {
                        messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                            if (it.seq == seq) it.copy(deleted = true, text = "", media = null) else it
                        }
                        if (activeChatId == chatId) activeMessages = messagesCache[chatId] ?: emptyList()
                    }
                }

                override fun onReaction(seq: Long, reactions: List<ReactionDto>) {
                    scope.launch {
                        messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                            if (it.seq == seq) it.copy(reactions = reactions) else it
                        }
                        if (activeChatId == chatId) activeMessages = messagesCache[chatId] ?: emptyList()
                    }
                }

                override fun onPin(seq: Long, pinned: Boolean) {
                    scope.launch {
                        messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                            if (it.seq == seq) it.copy(pinned = pinned) else it
                        }
                        if (activeChatId == chatId) activeMessages = messagesCache[chatId] ?: emptyList()
                    }
                }

                override fun onPoll(seq: Long, poll: PollDto) {
                    scope.launch {
                        messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                            if (it.seq == seq) it.copy(poll = poll) else it
                        }
                        if (activeChatId == chatId) activeMessages = messagesCache[chatId] ?: emptyList()
                    }
                }

                override fun onClosed() {
                    scope.launch {
                        delay(2500)
                        if (activeChatId == chatId && token != null) connectRealtime(chatId)
                    }
                }
            },
        )
    }

    // ------------------------------------------------------------------ users

    fun loadUsers(query: String) {
        usersLoading = true
        scope.launch {
            try {
                usersDirectory = api.users(query).users
            } catch (e: Exception) {
                toast = e.message
            } finally {
                usersLoading = false
            }
        }
    }

    fun startChatWith(userId: String) {
        scope.launch {
            try {
                val resp = api.createChat(listOf(userId))
                refreshChats(silent = true)
                backStack.clear()
                backStack.add(Route.Chats)
                backStack.add(Route.Chat(resp.chat.id))
                enterChat(resp.chat.id)
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    // ------------------------------------------------------------------ admin

    fun loadAdminUsers() {
        if (me?.role != "admin") return
        scope.launch {
            try {
                adminUsers = api.adminUsers().users
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun adminCreateUser(
        username: String,
        password: String,
        displayName: String,
        role: String,
        onCreated: () -> Unit,
    ) {
        if (adminBusy) return
        adminBusy = true
        adminError = null
        scope.launch {
            try {
                api.adminCreateUser(username.trim(), password, displayName.trim().ifBlank { null }, role)
                adminUsers = api.adminUsers().users
                refreshChats(silent = true)
                onCreated()
            } catch (e: Exception) {
                adminError = e.message
            } finally {
                adminBusy = false
            }
        }
    }

    fun clearAdminError() {
        adminError = null
    }

    fun editMessage(seq: Long, text: String) {
        val chatId = activeChatId ?: return
        val content = text.trim()
        if (content.isEmpty()) return
        scope.launch {
            try {
                val resp = api.editMessage(chatId, seq, content)
                applyIncoming(chatId, resp.message)
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun deleteMessage(seq: Long) {
        val chatId = activeChatId ?: return
        scope.launch {
            try {
                api.deleteMessage(chatId, seq)
                messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                    if (it.seq == seq) it.copy(deleted = true, text = "", media = null) else it
                }
                activeMessages = messagesCache[chatId] ?: emptyList()
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun toggleReaction(seq: Long, emoji: String) {
        val chatId = activeChatId ?: return
        scope.launch {
            try {
                val resp = api.toggleReaction(chatId, seq, emoji)
                messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                    if (it.seq == seq) it.copy(reactions = resp.reactions) else it
                }
                activeMessages = messagesCache[chatId] ?: emptyList()
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun pinMessage(seq: Long, pinned: Boolean) {
        val chatId = activeChatId ?: return
        scope.launch {
            try {
                api.pinMessage(chatId, seq, pinned)
                messagesCache[chatId] = (messagesCache[chatId] ?: emptyList()).map {
                    if (it.seq == seq) it.copy(pinned = pinned) else it
                }
                activeMessages = messagesCache[chatId] ?: emptyList()
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun sendMedia(uri: Uri, kind: String) {
        val chatId = activeChatId ?: return
        scope.launch {
            try {
                val resolver = getApplication<Application>().contentResolver
                val mime = resolver.getType(uri) ?: "application/octet-stream"
                val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                } ?: when (kind) {
                    "image" -> "photo.jpg"
                    "video" -> "video.mp4"
                    else -> "file"
                }
                val bytes = withContext(Dispatchers.IO) {
                    resolver.openInputStream(uri)?.use { it.readBytes() }
                } ?: run {
                    toast = "无法读取文件"
                    return@launch
                }

                var width: Int? = null
                var height: Int? = null
                if (kind == "image") {
                    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
                    width = options.outWidth.takeIf { it > 0 }
                    height = options.outHeight.takeIf { it > 0 }
                }

                val media = api.uploadMedia(chatId, bytes, name, mime, kind, width, height).media
                val resp = api.sendMessage(chatId, "", UUID.randomUUID().toString(), mediaId = media.id)
                applyIncoming(chatId, resp.message)
            } catch (e: Exception) {
                toast = e.message
            }
        }
    }

    fun createGroup(title: String, memberIds: List<String>): Job = scope.launch {
        try {
            val chat = api.createGroup(title, memberIds).chat
            refreshChats(silent = false)
            enterChat(chat.id)
        } catch (e: Exception) {
            toast = e.message
        }
    }

    fun createChannel(title: String, username: String?, description: String): Job = scope.launch {
        try {
            val chat = api.createChannel(title, username, description).chat
            refreshChats(silent = false)
            enterChat(chat.id)
        } catch (e: Exception) {
            toast = e.message
        }
    }

    fun batchChats(action: String, chatIds: List<String>): Job = scope.launch {
        try {
            api.batchChats(action, chatIds)
            refreshChats(silent = true)
        } catch (e: Exception) {
            toast = e.message
        }
    }

    fun updateChatFields(chatId: String, fields: Map<String, Any?>): Job = scope.launch {
        try {
            api.updateChat(chatId, fields)
            refreshChats(silent = true)
        } catch (e: Exception) {
            toast = e.message
        }
    }

    fun updateProfile(fields: Map<String, Any?>): Job = scope.launch {
        try {
            me = api.updateProfile(fields).user
        } catch (e: Exception) {
            toast = e.message
        }
    }

    // --------------------------------------------------------------- mappers

    private fun MessageDto.toUi(): UiMessage = UiMessage(
        key = "s:$seq",
        seq = seq,
        id = id,
        clientId = clientId,
        senderId = senderId,
        senderName = senderName,
        senderColor = senderColor,
        text = text,
        createdAt = createdAt,
        status = MessageStatus.SENT,
        media = media,
        replyTo = replyTo,
        editedAt = editedAt,
        deleted = deleted,
        forwardedFrom = forwardedFrom,
        pinned = pinned,
        reactions = reactions,
        poll = poll,
        views = views,
        topicId = topicId,
    )

    private fun ChatDto.toChatUi(myId: String?): ChatUi {
        val peer = members.firstOrNull { it.id != myId }
        val isGroup = type != "direct"
        val displayTitle = if (isGroup) (title?.ifBlank { null } ?: "群聊") else (peer?.displayName ?: "会话")
        val last = lastMessage
        val preview = when {
            last == null -> "暂无消息"
            last.senderId == myId -> "你：${last.text}"
            isGroup -> "${last.senderName}：${last.text}"
            else -> last.text
        }.replace("\n", " ")
        return ChatUi(
            id = id,
            isGroup = isGroup,
            title = displayTitle,
            avatarColor = if (isGroup) "#7BC862" else (peer?.avatarColor ?: "#3390EC"),
            peerId = peer?.id,
            lastText = preview,
            lastAt = last?.createdAt ?: createdAt,
            lastFromMe = last?.senderId == myId,
            unread = unread,
            otherReadSeq = otherReadSeq,
            members = members,
            type = type,
            pinned = pinned,
            archived = archived,
            folderId = folderId,
            wallpaper = wallpaper,
            myRole = myRole,
            description = description,
            announcement = announcement,
            slowMode = slowMode ?: 0,
            topicsEnabled = topicsEnabled ?: false,
            autoDeleteSeconds = autoDeleteSeconds ?: 0,
        )
    }
}
