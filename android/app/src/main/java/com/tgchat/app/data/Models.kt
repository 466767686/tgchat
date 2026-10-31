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
    val bio: String? = null,
    val lastSeenVisibility: String? = null,
    val readReceipts: Boolean? = null,
    val chatRole: String? = null,
    val mutedUntil: Long? = null,
) {
    val title: String get() = displayName.ifBlank { username }
    val isAdminRole: Boolean get() = chatRole == "admin" || chatRole == "owner"
    val isOwnerRole: Boolean get() = chatRole == "owner"
    val isMuted: Boolean get() = (mutedUntil ?: 0) > System.currentTimeMillis()

    val initials: String
        get() {
            val name = title
            val parts = name.trim().split(" ", "　").filter { it.isNotBlank() }
            return when {
                parts.size >= 2 -> (parts[0].take(1) + parts[1].take(1)).uppercase()
                else -> name.take(1).uppercase()
            }
        }
}

@Serializable
data class MediaDto(
    val id: String,
    val kind: String = "file",
    val mime: String = "application/octet-stream",
    val size: Long = 0,
    val name: String? = null,
    val width: Int? = null,
    val height: Int? = null,
    val durationMs: Int? = null,
    val url: String = "",
)

@Serializable
data class ReplyPreviewDto(
    val seq: Long,
    val senderName: String = "",
    val text: String = "",
)

@Serializable
data class ReactionDto(
    val emoji: String,
    val count: Int = 0,
    val me: Boolean = false,
)

@Serializable
data class PollOptionDto(
    val index: Int,
    val text: String,
    val votes: Int = 0,
)

@Serializable
data class PollDto(
    val id: String,
    val question: String,
    val options: List<PollOptionDto> = emptyList(),
    val multiple: Boolean = false,
    val anonymous: Boolean = false,
    val closed: Boolean = false,
    val totalVotes: Int = 0,
    val myVotes: List<Int> = emptyList(),
)

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
    val deleted: Boolean = false,
    val editedAt: Long? = null,
    val forwardedFrom: String? = null,
    val pinned: Boolean = false,
    val replyTo: ReplyPreviewDto? = null,
    val media: MediaDto? = null,
    val reactions: List<ReactionDto> = emptyList(),
    val topicId: String? = null,
    val poll: PollDto? = null,
    val views: Int? = null,
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
    val description: String? = null,
    val announcement: String? = null,
    val photoUrl: String? = null,
    val joinMode: String? = null,
    val slowMode: Int? = null,
    val historyVisible: Boolean? = null,
    val topicsEnabled: Boolean? = null,
    val username: String? = null,
    val isPublic: Boolean? = null,
    val discussionChatId: String? = null,
    val subscriberCount: Int? = null,
    val autoDeleteSeconds: Int? = null,
    val myRole: String? = null,
    val pinned: Boolean = false,
    val archived: Boolean = false,
    val folderId: String? = null,
    val wallpaper: String? = null,
) {
    val isGroup: Boolean get() = type == "group"
    val isChannel: Boolean get() = type == "channel"
    val isSaved: Boolean get() = type == "saved"
    val canManage: Boolean get() = myRole == "owner" || myRole == "admin"

    fun displayTitle(myId: String?): String {
        if (isSaved) return "收藏夹"
        if (isChannel) return title?.takeIf { it.isNotBlank() } ?: "频道"
        if (isGroup) return title?.takeIf { it.isNotBlank() } ?: "群聊"
        return members.firstOrNull { it.id != myId }?.title ?: "会话"
    }

    fun avatarColor(myId: String?): String = when {
        isSaved -> "#3390EC"
        isChannel -> "#E0A040"
        isGroup -> "#7BC862"
        else -> members.firstOrNull { it.id != myId }?.avatarColor ?: "#3390EC"
    }

    fun preview(myId: String?): String {
        val last = lastMessage ?: return "暂无消息"
        val prefix = when {
            last.senderId == myId -> "你："
            isGroup || isChannel -> "${last.senderName}："
            else -> ""
        }
        val body = when {
            last.deleted -> "消息已删除"
            last.poll != null -> "投票：${last.poll.question}"
            last.media != null -> when (last.media.kind) {
                "image" -> if (last.text.isNotBlank()) last.text else "图片"
                "video", "video_note" -> "视频"
                "voice" -> "语音"
                "sticker" -> "贴纸"
                "gif" -> "GIF"
                else -> last.media.name ?: "文件"
            }
            else -> last.text
        }
        return prefix + body.replace("\n", " ")
    }
}

@Serializable
data class TopicDto(
    val id: String,
    val chatId: String = "",
    val title: String,
    val emoji: String? = null,
    val closed: Boolean = false,
    val pinned: Boolean = false,
)

@Serializable
data class FolderDto(
    val id: String,
    val name: String,
    val position: Int? = null,
)

@Serializable
data class SessionDto(
    val id: String,
    val device: String = "设备",
    val platform: String = "",
    val createdAt: Long = 0,
    val lastActiveAt: Long = 0,
    val current: Boolean = false,
)

@Serializable
data class ChannelSummaryDto(
    val id: String,
    val title: String,
    val username: String? = null,
    val description: String? = null,
    val subscriberCount: Int = 0,
    val joined: Boolean = false,
)

@Serializable
data class LoginResponse(val token: String, val user: UserDto)

@Serializable
data class MeResponse(val user: UserDto)

@Serializable
data class UserResponse(val user: UserDto)

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
data class MediaResponse(val media: MediaDto)

@Serializable
data class ReactionsResponse(val reactions: List<ReactionDto> = emptyList())

@Serializable
data class PollResponse(val poll: PollDto)

@Serializable
data class TopicsResponse(val topics: List<TopicDto> = emptyList())

@Serializable
data class TopicResponse(val topic: TopicDto)

@Serializable
data class FoldersResponse(val folders: List<FolderDto> = emptyList())

@Serializable
data class FolderResponse(val folder: FolderDto)

@Serializable
data class SessionsResponse(val sessions: List<SessionDto> = emptyList())

@Serializable
data class ChannelsResponse(val channels: List<ChannelSummaryDto> = emptyList())

@Serializable
data class InviteResponse(val code: String, val link: String)

@Serializable
data class CreateUserResponse(val user: UserDto, val chatId: String? = null)

@Serializable
data class SimpleResponse(val ok: Boolean = true)

@Serializable
data class ErrorResponse(val error: String? = null, val code: String? = null)
