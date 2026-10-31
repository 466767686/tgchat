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

    var title: String { displayName.isEmpty ? username : displayName }

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

struct Message: Codable, Identifiable, Hashable {
    let seq: Int64
    let id: String
    let chatId: String
    let senderId: String
    let senderName: String
    let senderColor: String
    let text: String
    let createdAt: Int64
    let clientId: String?
    var media: Media? = nil
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

    var isGroup: Bool { type != "direct" }

    func peer(myId: String?) -> User? {
        members.first { $0.id != myId }
    }

    func displayTitle(myId: String?) -> String {
        if isGroup { return (title?.isEmpty == false ? title! : "群聊") }
        return peer(myId: myId)?.title ?? "会话"
    }

    func avatarColor(myId: String?) -> String {
        isGroup ? "#7BC862" : (peer(myId: myId)?.avatarColor ?? "#3390EC")
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
struct UsersResponse: Codable { let users: [User] }
struct ChatResponse: Codable { let chat: Chat; let created: Bool? }
struct SimpleResponse: Codable { let ok: Bool? }
struct CreateUserResponse: Codable { let user: User; let chatId: String? }
struct ErrorResponse: Codable { let error: String?; let code: String? }
