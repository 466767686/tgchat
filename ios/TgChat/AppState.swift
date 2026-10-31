import Foundation
import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var booting = true
    @Published var token: String?
    @Published var me: User?
    @Published var baseURL: String
    @Published var themeMode: ThemeMode
    @Published var locked = true
    @Published var disguiseEnabled: Bool {
        didSet { UserDefaults.standard.set(disguiseEnabled, forKey: "disguiseEnabled") }
    }

    @Published var chats: [Chat] = []
    @Published var chatsLoading = false

    @Published var loginLoading = false
    @Published var loginError: String?

    @Published var messages: [String: [Message]] = [:]
    @Published var typingName: String?
    @Published var toast: String?
    @Published var appActive = true

    @Published var usersDirectory: [User] = []
    @Published var adminUsers: [User] = []
    @Published var adminError: String?

    private let api = APIClient.shared
    private let realtime = RealtimeClient()
    private let inbox = RealtimeClient()
    private let defaults = UserDefaults.standard

    private var chatsPoll: Task<Void, Never>?
    private var chatPoll: Task<Void, Never>?
    private var typingReset: Task<Void, Never>?
    private var lastReadSent: [String: Int64] = [:]
    private var activeChatId: String?
    private var lastTypingAt = Date.distantPast
    private var pendingChatId: String?

    init() {
        let savedBase = defaults.string(forKey: "baseURL") ?? Config.defaultBaseURL
        baseURL = savedBase
        api.baseURL = savedBase
        themeMode = ThemeMode(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        disguiseEnabled = UserDefaults.standard.object(forKey: "disguiseEnabled") as? Bool ?? true
        locked = disguiseEnabled
        if let savedToken = defaults.string(forKey: "token"), !savedToken.isEmpty {
            token = savedToken
            api.token = savedToken
            if let data = defaults.data(forKey: "me") {
                me = try? JSONDecoder().decode(User.self, from: data)
            }
        }
        Task { await bootstrap() }
    }

    var isLoggedIn: Bool { token != nil }

    // MARK: - Session

    func bootstrap() async {
        guard token != nil else {
            booting = false
            return
        }
        do {
            let response = try await api.me()
            me = response.user
            persistUser()
            await loadChats(silent: false)
            startChatsPolling()
            connectInbox()
        } catch {
            if me == nil { clearSession() }
        }
        booting = false
    }

    func login(username: String, password: String) async {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty else {
            loginError = "请输入用户名和密码"
            return
        }
        loginLoading = true
        loginError = nil
        do {
            let response = try await api.login(username: name, password: password)
            token = response.token
            api.token = response.token
            me = response.user
            persistUser()
            await loadChats(silent: false)
            startChatsPolling()
            connectInbox()
        } catch {
            loginError = error.localizedDescription
        }
        loginLoading = false
    }

    func logout() async {
        await api.logout()
        realtime.disconnect()
        inbox.disconnect()
        chatsPoll?.cancel()
        chatPoll?.cancel()
        clearSession()
        lock()
    }

    private func clearSession() {
        token = nil
        me = nil
        api.token = nil
        chats = []
        messages = [:]
        defaults.removeObject(forKey: "token")
        defaults.removeObject(forKey: "me")
    }

    private func persistUser() {
        if let token = token { defaults.set(token, forKey: "token") }
        if let me = me, let data = try? JSONEncoder().encode(me) {
            defaults.set(data, forKey: "me")
        }
    }

    func setBaseURL(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !value.hasPrefix("http://") && !value.hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        baseURL = value
        api.baseURL = value
        defaults.set(value, forKey: "baseURL")
        if token != nil { connectInbox() }
    }

    func setTheme(_ mode: ThemeMode) {
        themeMode = mode
        defaults.set(mode.rawValue, forKey: "theme")
    }

    // MARK: - Calculator disguise

    var unlockPin: String { defaults.string(forKey: "unlockPin") ?? "1234" }

    func setPin(_ pin: String) {
        defaults.set(pin, forKey: "unlockPin")
    }

    func setDisguise(_ enabled: Bool) {
        disguiseEnabled = enabled
        if enabled { locked = true }
    }

    func unlock() {
        locked = false
    }

    func lock() {
        if disguiseEnabled { locked = true }
    }

    func clearToast() {
        toast = nil
    }

    // MARK: - Chats

    func loadChats(silent: Bool = true) async {
        guard token != nil else { return }
        if !silent { chatsLoading = true }
        do {
            chats = try await api.chats().chats
        } catch {
            if !silent { toast = error.localizedDescription }
        }
        if !silent { chatsLoading = false }
    }

    func startChatsPolling() {
        chatsPoll?.cancel()
        chatsPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self else { return }
                if self.activeChatId == nil {
                    await self.loadChats(silent: true)
                }
            }
        }
    }

    func openChat(_ chatId: String) async {
        activeChatId = chatId
        typingName = nil
        if messages[chatId] == nil { messages[chatId] = [] }
        await loadMessages(chatId: chatId)
        connectRealtime(chatId)
        startChatPolling(chatId: chatId)
    }

    func closeChat() {
        activeChatId = nil
        typingName = nil
        realtime.disconnect()
        chatPoll?.cancel()
    }

    func loadMessages(chatId: String) async {
        do {
            let response = try await api.messages(chatId: chatId)
            messages[chatId] = merge(messages[chatId] ?? [], response.messages)
            if let last = messages[chatId]?.last(where: { $0.seq > 0 }) {
                markRead(chatId, seq: last.seq)
            }
        } catch {
            // keep whatever we already have
        }
    }

    private func startChatPolling(chatId: String) {
        chatPoll?.cancel()
        chatPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self = self, self.activeChatId == chatId else { return }
                if let response = try? await self.api.messages(chatId: chatId, before: 0, limit: 40) {
                    self.messages[chatId] = self.merge(self.messages[chatId] ?? [], response.messages)
                    if let last = self.messages[chatId]?.last(where: { $0.seq > 0 }) {
                        self.markRead(chatId, seq: last.seq)
                    }
                }
            }
        }
    }

    // MARK: - Messages

    func sendMessage(_ text: String, chatId: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let me = me else { return }
        let clientId = UUID().uuidString
        let local = Message(
            seq: 0,
            id: "local-\(clientId)",
            chatId: chatId,
            senderId: me.id,
            senderName: me.title,
            senderColor: me.avatarColor,
            text: content,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            clientId: clientId
        )
        messages[chatId] = (messages[chatId] ?? []) + [local]
        do {
            let response = try await api.sendMessage(chatId: chatId, text: content, clientId: clientId)
            messages[chatId] = merge(messages[chatId] ?? [], [response.message])
            if let last = messages[chatId]?.last(where: { $0.seq > 0 }) {
                markRead(chatId, seq: last.seq)
            }
            await loadChats(silent: true)
        } catch {
            toast = error.localizedDescription
            messages[chatId]?.removeAll { $0.clientId == clientId && $0.seq == 0 }
        }
    }

    func sendTyping() {
        let now = Date()
        guard now.timeIntervalSince(lastTypingAt) > 1.5 else { return }
        lastTypingAt = now
        realtime.sendTyping()
    }

    private func merge(_ existing: [Message], _ incoming: [Message]) -> [Message] {
        var result = existing
        for message in incoming {
            if let clientId = message.clientId,
               let index = result.firstIndex(where: { $0.clientId == clientId && $0.seq == 0 }) {
                result.remove(at: index)
            }
            if let index = result.firstIndex(where: { $0.id == message.id }) {
                result[index] = message
            } else {
                result.append(message)
            }
        }
        return result.sorted { a, b in
            if a.seq == 0 && b.seq == 0 { return a.createdAt < b.createdAt }
            if a.seq == 0 { return false }
            if b.seq == 0 { return true }
            return a.seq < b.seq
        }
    }

    private func markRead(_ chatId: String, seq: Int64) {
        guard seq > 0, (lastReadSent[chatId] ?? 0) < seq else { return }
        lastReadSent[chatId] = seq
        if let index = chats.firstIndex(where: { $0.id == chatId }) {
            let chat = chats[index]
            chats[index] = Chat(
                id: chat.id,
                type: chat.type,
                title: chat.title,
                createdAt: chat.createdAt,
                lastReadSeq: seq,
                otherReadSeq: chat.otherReadSeq,
                unread: 0,
                lastMessage: chat.lastMessage,
                members: chat.members
            )
        }
        Task { await api.markRead(chatId: chatId, seq: seq) }
    }

    // MARK: - Realtime

    private func connectRealtime(_ chatId: String) {
        guard let token = token else { return }
        realtime.onMessage = { [weak self] message in
            Task { @MainActor in
                guard let self = self else { return }
                if self.activeChatId == chatId {
                    self.messages[chatId] = self.merge(self.messages[chatId] ?? [], [message])
                    if let last = self.messages[chatId]?.last(where: { $0.seq > 0 }) {
                        self.markRead(chatId, seq: last.seq)
                    }
                }
                await self.loadChats(silent: true)
            }
        }
        realtime.onTyping = { [weak self] name in
            Task { @MainActor in
                guard let self = self, self.activeChatId == chatId else { return }
                self.typingName = name.isEmpty ? "对方" : name
                self.typingReset?.cancel()
                self.typingReset = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    guard let self = self else { return }
                    if !Task.isCancelled { self.typingName = nil }
                }
            }
        }
        realtime.onRead = { [weak self] seq in
            Task { @MainActor in
                guard let self = self,
                      let index = self.chats.firstIndex(where: { $0.id == chatId }) else { return }
                let chat = self.chats[index]
                guard seq > chat.otherReadSeq else { return }
                self.chats[index] = Chat(
                    id: chat.id,
                    type: chat.type,
                    title: chat.title,
                    createdAt: chat.createdAt,
                    lastReadSeq: chat.lastReadSeq,
                    otherReadSeq: seq,
                    unread: chat.unread,
                    lastMessage: chat.lastMessage,
                    members: chat.members
                )
            }
        }
        realtime.connect(baseURL: baseURL, chatId: chatId, token: token)
    }

    // MARK: - Background inbox (local notifications)

    private func connectInbox() {
        guard let token = token else { return }
        inbox.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleInboxMessage(message)
            }
        }
        inbox.onClosed = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self = self, self.token != nil else { return }
                self.connectInbox()
            }
        }
        inbox.connectUser(baseURL: baseURL, token: token)
    }

    private func handleInboxMessage(_ message: Message) {
        if let existing = messages[message.chatId] {
            messages[message.chatId] = merge(existing, [message])
        }
        Task { await loadChats(silent: true) }

        if appActive && activeChatId == message.chatId { return }
        LocalNotifications.show(message)
    }

    func requestOpenChat(_ chatId: String) {
        if chats.contains(where: { $0.id == chatId }) {
            Task { await openChat(chatId) }
            return
        }
        pendingChatId = chatId
        Task {
            await loadChats(silent: true)
            if let id = pendingChatId, chats.contains(where: { $0.id == id }) {
                pendingChatId = nil
                await openChat(id)
            }
        }
    }

    // MARK: - Users

    func loadUsers(query: String = "") async {
        do {
            usersDirectory = try await api.users(query: query).users
        } catch {
            toast = error.localizedDescription
        }
    }

    func startChat(with userId: String) async -> Chat? {
        do {
            let response = try await api.createChat(memberIds: [userId])
            await loadChats(silent: true)
            return response.chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    // MARK: - Admin

    func loadAdminUsers() async {
        guard me?.role == "admin" else { return }
        do {
            adminUsers = try await api.adminUsers().users
        } catch {
            toast = error.localizedDescription
        }
    }

    func adminCreateUser(username: String, password: String, displayName: String, role: String) async -> Bool {
        adminError = nil
        do {
            _ = try await api.adminCreateUser(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespaces),
                role: role
            )
            await loadAdminUsers()
            await loadChats(silent: true)
            return true
        } catch {
            adminError = error.localizedDescription
            return false
        }
    }
}
