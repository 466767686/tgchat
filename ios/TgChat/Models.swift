import Foundation

enum Config {
    /// 与 Android 客户端使用同一个后端。
    static let defaultBaseURL = "https://chat.132778.xyz"
    static let appVersion = "1.0.0"
}

// MARK: - DTOs (must match the Worker's JSON)

struct User: Codable, Identifiable, Hashable {
    let id: String
    var username: String
    var displayName: String
    var avatarColor: String
    var role: String
    var lastSeenAt: Int64?
    var chatRole: String? = nil
    var mutedUntil: Int64? = nil
    var bio: String? = nil
    var lastSeenVisibility: String? = nil
    var readReceipts: Bool? = nil

    var title: String { displayName.isEmpty ? username : displayName }
    var isOwnerRole: Bool { chatRole == "owner" }
    var isAdminRole: Bool { chatRole == "admin" || chatRole == "owner" }
    var isMuted: Bool {
        guard let mutedUntil = mutedUntil, mutedUntil > 0 else { return false }
        return mutedUntil > Int64(Date().timeIntervalSince1970 * 1000)
    }

    var initials: String {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "?" }
        let parts = name.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return String((parts[0].first.map(String.init) ?? "") + (parts[1].first.map(String.init) ?? "")).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }
}

struct Media: Codable, Identifiable, Hashable {
    let id: String
    let kind: String          // image | video | file | voice | sticker | gif
    let mime: String
    let size: Int
    let name: String?
    let width: Int?
    let height: Int?
    let durationMs: Int?
    let url: String

    var isImage: Bool { kind == "image" || kind == "sticker" || kind == "gif" }
    var isVideo: Bool { kind == "video" }
    var isVoice: Bool { kind == "voice" }
    var isFile: Bool { kind == "file" }

    var displayName: String { name ?? "文件" }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct PollOption: Codable, Hashable {
    let index: Int
    let text: String
    var votes: Int
}

struct Poll: Codable, Hashable {
    let id: String
    let question: String
    var options: [PollOption]
    let multiple: Bool
    let anonymous: Bool
    var closed: Bool
    var totalVotes: Int
    var myVotes: [Int]
}

struct Topic: Codable, Identifiable, Hashable {
    let id: String
    let chatId: String
    let title: String
    let emoji: String?
    var closed: Bool
    var pinned: Bool
}

struct ReplyPreview: Codable, Hashable {
    let seq: Int64
    let senderName: String
    let text: String
}

struct Reaction: Codable, Hashable {
    let emoji: String
    let count: Int
    let me: Bool
}

struct Message: Codable, Identifiable, Hashable {
    let seq: Int64
    let id: String
    let chatId: String
    let senderId: String
    let senderName: String
    let senderColor: String
    var text: String
    let createdAt: Int64
    let clientId: String?
    var media: Media? = nil
    var deleted: Bool = false
    var editedAt: Int64? = nil
    var forwardedFrom: String? = nil
    var pinned: Bool = false
    var replyTo: ReplyPreview? = nil
    var reactions: [Reaction] = []
    var topicId: String? = nil
    var poll: Poll? = nil
    var views: Int? = nil
}

struct Chat: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String?
    let createdAt: Int64
    let lastReadSeq: Int64
    let otherReadSeq: Int64
    let unread: Int
    let lastMessage: Message?
    let members: [User]
    var description: String? = nil
    var announcement: String? = nil
    var photoUrl: String? = nil
    var joinMode: String? = nil
    var myRole: String? = nil
    var slowMode: Int? = nil
    var historyVisible: Bool? = nil
    var topicsEnabled: Bool? = nil
    var username: String? = nil
    var isPublic: Bool? = nil
    var discussionChatId: String? = nil
    var subscriberCount: Int? = nil
    var pinned: Bool = false
    var archived: Bool = false
    var folderId: String? = nil
    var wallpaper: String? = nil
    var autoDeleteSeconds: Int? = nil

    var isGroup: Bool { type == "group" }
    var isSaved: Bool { type == "saved" }
    var isChannel: Bool { type == "channel" }
    var isOwner: Bool { myRole == "owner" }
    var canManage: Bool { myRole == "owner" || myRole == "admin" }

    func peer(myId: String?) -> User? {
        members.first { $0.id != myId }
    }

    func displayTitle(myId: String?) -> String {
        if isSaved { return "收藏夹" }
        if isChannel { return (title?.isEmpty == false ? title! : "频道") }
        if isGroup { return (title?.isEmpty == false ? title! : "群聊") }
        return peer(myId: myId)?.title ?? "会话"
    }

    func avatarColor(myId: String?) -> String {
        if isSaved { return "#3390EC" }
        if isChannel { return "#E0A040" }
        if isGroup { return "#7BC862" }
        return peer(myId: myId)?.avatarColor ?? "#3390EC"
    }

    func preview(myId: String?) -> String {
        guard let last = lastMessage else { return "暂无消息" }
        let prefix: String
        if last.senderId == myId {
            prefix = "你："
        } else if isGroup {
            prefix = "\(last.senderName)："
        } else {
            prefix = ""
        }
        return (prefix + last.text).replacingOccurrences(of: "\n", with: " ")
    }
}

struct LoginResponse: Codable { let token: String; let user: User }
struct MediaUploadResponse: Codable { let media: Media }
struct MeResponse: Codable { let user: User }
struct ChatsResponse: Codable { let chats: [Chat] }
struct MessagesResponse: Codable { let messages: [Message]; let hasMore: Bool }
struct MessageResponse: Codable { let message: Message; let duplicate: Bool? }
struct ReactionsResponse: Codable { let reactions: [Reaction] }
struct UsersResponse: Codable { let users: [User] }
struct ChatResponse: Codable { let chat: Chat; let created: Bool? }
struct InviteResponse: Codable { let code: String; let link: String }
struct TopicsResponse: Codable { let topics: [Topic] }

struct Folder: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    let position: Int?
}

struct FoldersResponse: Codable { let folders: [Folder] }

struct ChannelSummary: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let username: String?
    let description: String?
    let subscriberCount: Int
    let joined: Bool
}
struct ChannelsResponse: Codable { let channels: [ChannelSummary] }

struct SessionInfo: Codable, Identifiable, Hashable {
    let id: String
    let device: String
    let platform: String
    let createdAt: Int64
    let lastActiveAt: Int64
    let current: Bool
}
struct SessionsResponse: Codable { let sessions: [SessionInfo] }

struct TelegramSticker: Codable, Hashable {
    let fileId: String
    let emoji: String?
    let animated: Bool
    let video: Bool
}

struct StickerSetResponse: Codable {
    let name: String
    let title: String
    let animated: Bool
    let video: Bool
    let stickers: [TelegramSticker]
}
struct UserResponse: Codable { let user: User }
struct FolderResponse: Codable { let folder: Folder }
struct TopicResponse: Codable { let topic: Topic }
struct PollResponse: Codable { let poll: Poll }
struct ReportItem: Codable, Identifiable {
    let id: String
    let seq: Int64
    let reporter: String
    let reason: String
    let text: String
    let status: String
    let createdAt: Int64
}
struct ReportsResponse: Codable { let reports: [ReportItem] }
struct SimpleResponse: Codable { let ok: Bool? }
struct CreateUserResponse: Codable { let user: User; let chatId: String? }
struct ErrorResponse: Codable { let error: String?; let code: String? }
