import Foundation

enum ApiError: Error, LocalizedError {
    case network(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .network(let message), .server(let message): return message
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    var baseURL: String = Config.defaultBaseURL
    var token: String?

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        session = URLSession(configuration: configuration)
    }

    private func url(for path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        auth: Bool = true
    ) async throws -> T {
        guard let url = url(for: path) else { throw ApiError.network("服务器地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if auth, let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ApiError.network("无法连接服务器，请检查网络或服务器地址")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network("网络异常，请稍后重试")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let parsed = try? decoder.decode(ErrorResponse.self, from: data), let message = parsed.error {
                throw ApiError.server(message)
            }
            throw ApiError.server("请求失败（HTTP \(http.statusCode)）")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiError.server("服务器返回了无法识别的数据")
        }
    }

    // MARK: - Endpoints

    func login(username: String, password: String) async throws -> LoginResponse {
        try await request("/api/auth/login", method: "POST", body: ["username": username, "password": password], auth: false)
    }

    func logout() async {
        let _: SimpleResponse? = try? await request("/api/auth/logout", method: "POST")
    }

    func me() async throws -> MeResponse {
        try await request("/api/me")
    }

    func chats() async throws -> ChatsResponse {
        try await request("/api/chats")
    }

    func messages(chatId: String, before: Int64 = 0, limit: Int = 60, topicId: String? = nil) async throws -> MessagesResponse {
        var path = "/api/chats/\(chatId)/messages?before=\(before)&limit=\(limit)"
        if let topicId = topicId, !topicId.isEmpty {
            path += "&topic=\(topicId)"
        }
        return try await request(path)
    }

    func sendMessage(
        chatId: String,
        text: String,
        clientId: String,
        mediaId: String? = nil,
        replyTo: Int64? = nil,
        forwardedFrom: String? = nil,
        topicId: String? = nil
    ) async throws -> MessageResponse {
        var body: [String: Any] = ["text": text, "clientId": clientId]
        if let mediaId = mediaId { body["mediaId"] = mediaId }
        if let replyTo = replyTo { body["replyTo"] = Int(replyTo) }
        if let forwardedFrom = forwardedFrom { body["forwardedFrom"] = forwardedFrom }
        if let topicId = topicId { body["topicId"] = topicId }
        return try await request("/api/chats/\(chatId)/messages", method: "POST", body: body)
    }

    func editMessage(chatId: String, seq: Int64, text: String) async throws -> MessageResponse {
        try await request(
            "/api/chats/\(chatId)/messages/\(seq)",
            method: "PATCH",
            body: ["text": text]
        )
    }

    func deleteMessage(chatId: String, seq: Int64) async throws {
        let _: SimpleResponse = try await request("/api/chats/\(chatId)/messages/\(seq)", method: "DELETE")
    }

    func toggleReaction(chatId: String, seq: Int64, emoji: String) async throws -> ReactionsResponse {
        try await request(
            "/api/chats/\(chatId)/messages/\(seq)/reactions",
            method: "POST",
            body: ["emoji": emoji]
        )
    }

    func pinMessage(chatId: String, seq: Int64, pinned: Bool) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/pin",
            method: "POST",
            body: ["seq": Int(seq), "pinned": pinned]
        )
    }

    func topics(chatId: String) async throws -> TopicsResponse {
        try await request("/api/chats/\(chatId)/topics")
    }

    func createTopic(chatId: String, title: String, emoji: String? = nil) async throws -> TopicResponse {
        var body: [String: Any] = ["title": title]
        if let emoji = emoji { body["emoji"] = emoji }
        return try await request("/api/chats/\(chatId)/topics", method: "POST", body: body)
    }

    func updateTopic(chatId: String, topicId: String, fields: [String: Any]) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/topics/\(topicId)",
            method: "PATCH",
            body: fields
        )
    }

    func createPoll(
        chatId: String,
        question: String,
        options: [String],
        multiple: Bool,
        anonymous: Bool = false,
        topicId: String? = nil
    ) async throws -> MessageResponse {
        var body: [String: Any] = [
            "question": question,
            "options": options,
            "multiple": multiple,
            "anonymous": anonymous,
        ]
        if let topicId = topicId { body["topicId"] = topicId }
        return try await request("/api/chats/\(chatId)/polls", method: "POST", body: body)
    }

    func votePoll(chatId: String, pollId: String, optionIndex: Int) async throws -> PollResponse {
        try await request(
            "/api/chats/\(chatId)/polls/\(pollId)/vote",
            method: "POST",
            body: ["optionIndex": optionIndex]
        )
    }

    func reportMessage(chatId: String, seq: Int64, reason: String) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/messages/\(seq)/report",
            method: "POST",
            body: ["reason": reason]
        )
    }

    func reports(chatId: String) async throws -> ReportsResponse {
        try await request("/api/chats/\(chatId)/reports")
    }

    func resolveReport(chatId: String, reportId: String) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/reports/\(reportId)",
            method: "POST"
        )
    }

    func batchChats(_ action: String, chatIds: [String]) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/batch",
            method: "POST",
            body: ["action": action, "chatIds": chatIds]
        )
    }

    func folders() async throws -> FoldersResponse {
        try await request("/api/folders")
    }

    func createFolder(name: String) async throws -> FolderResponse {
        try await request("/api/folders", method: "POST", body: ["name": name])
    }

    func deleteFolder(id: String) async throws {
        let _: SimpleResponse = try await request("/api/folders/\(id)", method: "DELETE")
    }

    func assignFolder(chatId: String, folderId: String?) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/folder",
            method: "PATCH",
            body: ["folderId": folderId ?? NSNull()]
        )
    }

    func setWallpaper(chatId: String, wallpaper: String?) async throws {
        let _: SimpleResponse = try await request(
            "/api/chats/\(chatId)/wallpaper",
            method: "POST",
            body: ["wallpaper": wallpaper ?? NSNull()]
        )
    }

    func savedChat() async throws -> ChatResponse {
        try await request("/api/saved", method: "POST")
    }

    func globalSearch(query: String, kind: String = "") async throws -> MessagesResponse {
        var path = "/api/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if !kind.isEmpty { path += "&kind=\(kind)" }
        return try await request(path)
    }

    func searchMessages(chatId: String, query: String) async throws -> MessagesResponse {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request("/api/chats/\(chatId)/search?q=\(escaped)")
    }

    func mediaURL(_ path: String) -> URL? {
        url(for: path)
    }

    /// Multipart upload with progress. Files up to 50 MB (server limit).
    func uploadMedia(
        chatId: String,
        fileURL: URL,
        kind: String,
        mime: String,
        name: String,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil,
        progress: @escaping (Double) -> Void
    ) async throws -> Media {
        guard let endpoint = url(for: "/api/chats/\(chatId)/media") else {
            throw ApiError.network("服务器地址无效")
        }
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw ApiError.server("无法读取文件")
        }

        let boundary = "----TgChat\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        func field(_ key: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        field("kind", kind)
        field("name", name.replacingOccurrences(of: "\"", with: ""))
        if let width = width { field("width", String(width)) }
        if let height = height { field("height", String(height)) }
        if let durationMs = durationMs { field("durationMs", String(durationMs)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name.replacingOccurrences(of: "\"", with: ""))\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let delegate = UploadProgressDelegate(onProgress: progress)
        let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await uploadSession.upload(for: request, from: body)
        } catch {
            throw ApiError.network("上传失败，请检查网络")
        }

        guard let http = response as? HTTPURLResponse else {
            throw ApiError.network("上传失败")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let parsed = try? decoder.decode(ErrorResponse.self, from: data), let message = parsed.error {
                throw ApiError.server(message)
            }
            throw ApiError.server("上传失败（HTTP \(http.statusCode)）")
        }
        do {
            return try decoder.decode(MediaUploadResponse.self, from: data).media
        } catch {
            throw ApiError.server("上传响应无法解析")
        }
    }

    func markRead(chatId: String, seq: Int64) async {
        let _: SimpleResponse? = try? await request("/api/chats/\(chatId)/read", method: "POST", body: ["seq": seq])
    }

    func users(query: String = "") async throws -> UsersResponse {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request("/api/users?query=\(escaped)")
    }

    func createGroup(title: String, memberIds: [String], description: String = "") async throws -> ChatResponse {
        try await request(
            "/api/chats",
            method: "POST",
            body: [
                "type": "group",
                "title": title,
                "description": description,
                "memberIds": memberIds,
            ]
        )
    }

    func updateChat(chatId: String, fields: [String: Any]) async throws -> ChatResponse {
        try await request("/api/chats/\(chatId)", method: "PATCH", body: fields)
    }

    func addMember(chatId: String, userId: String) async throws -> ChatResponse {
        try await request("/api/chats/\(chatId)/members", method: "POST", body: ["userId": userId])
    }

    func removeMember(chatId: String, userId: String) async throws {
        let _: SimpleResponse = try await request("/api/chats/\(chatId)/members/\(userId)", method: "DELETE")
    }

    func setMemberRole(chatId: String, userId: String, role: String) async throws -> ChatResponse {
        try await request("/api/chats/\(chatId)/members/\(userId)", method: "PATCH", body: ["role": role])
    }

    func muteMember(chatId: String, userId: String, until: Int64) async throws -> ChatResponse {
        try await request("/api/chats/\(chatId)/members/\(userId)", method: "PATCH", body: ["mutedUntil": Int(until)])
    }

    func createInvite(chatId: String, expiresInDays: Int = 0) async throws -> InviteResponse {
        try await request("/api/chats/\(chatId)/invite", method: "POST", body: ["expiresInDays": expiresInDays])
    }

    func revokeInvite(chatId: String, code: String) async throws {
        let _: SimpleResponse = try await request("/api/chats/\(chatId)/invite/\(code)", method: "DELETE")
    }

    func joinChat(code: String) async throws -> ChatResponse {
        try await request("/api/chats/join", method: "POST", body: ["code": code])
    }

    func leaveChat(chatId: String) async throws {
        let _: SimpleResponse = try await request("/api/chats/\(chatId)/leave", method: "POST")
    }

    func dissolveChat(chatId: String) async throws {
        let _: SimpleResponse = try await request("/api/chats/\(chatId)", method: "DELETE")
    }

    func createChat(memberIds: [String], title: String? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["memberIds": memberIds]
        if let title = title { body["title"] = title }
        return try await request("/api/chats", method: "POST", body: body)
    }

    func adminCreateUser(username: String, password: String, displayName: String?, role: String) async throws -> CreateUserResponse {
        var body: [String: Any] = ["username": username, "password": password, "role": role]
        if let displayName = displayName, !displayName.isEmpty { body["displayName"] = displayName }
        return try await request("/api/admin/users", method: "POST", body: body)
    }

    func adminUsers() async throws -> UsersResponse {
        try await request("/api/admin/users")
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
    }
}
