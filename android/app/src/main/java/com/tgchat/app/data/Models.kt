package com.tgchat.app.data

import kotlinx.serialization.Serializable

@Serializable
data class UserDto(
    val id: String,
    val username: String,
    val displayName: String = "",
    val avatarColor: String = "#3390EC",
    val role: String = "user",
    val lastSeenAt: Long? = null,
) {
    val initials: String
        get() {
            val name = displayName.ifBlank { username }
            val parts = name.trim().split(" ", "　").filter { it.isNotBlank() }
            return when {
                parts.size >= 2 -> (parts[0].take(1) + parts[1].take(1)).uppercase()
                else -> name.take(1).uppercase()
            }
        }
}

@Serializable
data class MessageDto(
    val seq: Long = 0,
    val id: String,
    val chatId: String = "",
    val senderId: String = "",
    val senderName: String = "",
    val senderColor: String = "#3390EC",
    val text: String = "",
    val createdAt: Long = 0,
    val clientId: String? = null,
)

@Serializable
data class ChatDto(
    val id: String,
    val type: String = "direct",
    val title: String? = null,
    val createdAt: Long = 0,
    val lastReadSeq: Long = 0,
    val otherReadSeq: Long = 0,
    val unread: Int = 0,
    val lastMessage: MessageDto? = null,
    val members: List<UserDto> = emptyList(),
)

@Serializable
data class LoginResponse(val token: String, val user: UserDto)

@Serializable
data class MeResponse(val user: UserDto)

@Serializable
data class ChatsResponse(val chats: List<ChatDto> = emptyList())

@Serializable
data class MessagesResponse(val messages: List<MessageDto> = emptyList(), val hasMore: Boolean = false)

@Serializable
data class MessageResponse(val message: MessageDto, val duplicate: Boolean = false)

@Serializable
data class UsersResponse(val users: List<UserDto> = emptyList())

@Serializable
data class ChatResponse(val chat: ChatDto, val created: Boolean = false)

@Serializable
data class CreateUserResponse(val user: UserDto, val chatId: String? = null)

@Serializable
data class SimpleResponse(val ok: Boolean = true)

@Serializable
data class ErrorResponse(val error: String? = null, val code: String? = null)
