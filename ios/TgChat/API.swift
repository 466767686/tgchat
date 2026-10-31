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

    func messages(chatId: String, before: Int64 = 0, limit: Int = 60) async throws -> MessagesResponse {
        try await request("/api/chats/\(chatId)/messages?before=\(before)&limit=\(limit)")
    }

    func sendMessage(chatId: String, text: String, clientId: String) async throws -> MessageResponse {
        try await request("/api/chats/\(chatId)/messages", method: "POST", body: ["text": text, "clientId": clientId])
    }

    func markRead(chatId: String, seq: Int64) async {
        let _: SimpleResponse? = try? await request("/api/chats/\(chatId)/read", method: "POST", body: ["seq": seq])
    }

    func users(query: String = "") async throws -> UsersResponse {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await request("/api/users?query=\(escaped)")
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
