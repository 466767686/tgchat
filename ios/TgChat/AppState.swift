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
    @Published var uploadProgress: Double? = nil
    @Published var uploadName: String? = nil
    @Published var uploadFailed = false
    @Published var hasMore: [String: Bool] = [:]
    @Published var loadingOlder = false
    @Published var folders: [Folder] = []

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
    private var pendingUpload: PendingUpload?
    private var uploadTask: Task<Void, Never>?

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
        await refreshChat(chatId)
        await loadMessages(chatId: chatId)
        connectRealtime(chatId)
        startChatPolling(chatId: chatId)
    }

    /// Pulls fresh metadata for one chat so `myRole`, members and settings are
    /// never stale when a screen opens.
    func refreshChat(_ chatId: String) async {
        if let chat = try? await api.chat(id: chatId).chat {
            replaceChat(chat)
        }
    }

    func refreshActiveChat() async {
        guard let chatId = activeChatId else { return }
        await refreshChat(chatId)
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
            hasMore[chatId] = response.hasMore
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

    func sendMessage(
        _ text: String,
        chatId: String,
        replyTo: Int64? = nil,
        forwardedFrom: String? = nil,
        topicId: String? = nil
    ) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let me = me else { return }
        let clientId = UUID().uuidString
        var localReply: ReplyPreview? = nil
        if let replyTo = replyTo, let target = messages[chatId]?.first(where: { $0.seq == replyTo }) {
            localReply = ReplyPreview(seq: replyTo, senderName: target.senderName, text: target.text)
        }
        let local = Message(
            seq: 0,
            id: "local-\(clientId)",
            chatId: chatId,
            senderId: me.id,
            senderName: me.title,
            senderColor: me.avatarColor,
            text: content,
            createdAt: Int64(Date().timeIntervalSince1970 * 1000),
            clientId: clientId,
            forwardedFrom: forwardedFrom,
            replyTo: localReply,
            topicId: topicId
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

    // MARK: - Message interactions

    func editMessage(chatId: String, seq: Int64, text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        do {
            let response = try await api.editMessage(chatId: chatId, seq: seq, text: content)
            replaceMessage(chatId: chatId, message: response.message)
            await loadChats(silent: true)
        } catch {
            toast = error.localizedDescription
        }
    }

    func deleteMessage(chatId: String, seq: Int64) async {
        do {
            try await api.deleteMessage(chatId: chatId, seq: seq)
            if var list = messages[chatId], let index = list.firstIndex(where: { $0.seq == seq }) {
                list[index].deleted = true
                list[index].text = ""
                list[index].media = nil
                messages[chatId] = list
            }
            await loadChats(silent: true)
        } catch {
            toast = error.localizedDescription
        }
    }

    func toggleReaction(chatId: String, seq: Int64, emoji: String) async {
        do {
            let response = try await api.toggleReaction(chatId: chatId, seq: seq, emoji: emoji)
            if var list = messages[chatId], let index = list.firstIndex(where: { $0.seq == seq }) {
                list[index].reactions = response.reactions
                messages[chatId] = list
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func pinMessage(chatId: String, seq: Int64, pinned: Bool) async {
        do {
            try await api.pinMessage(chatId: chatId, seq: seq, pinned: pinned)
            if var list = messages[chatId], let index = list.firstIndex(where: { $0.seq == seq }) {
                list[index].pinned = pinned
                messages[chatId] = list
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func createChannel(title: String, username: String?, description: String) async -> Chat? {
        do {
            let chat = try await api.createChannel(title: title, username: username, description: description).chat
            await loadChats(silent: true)
            return chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func discoverChannels(query: String) async -> [ChannelSummary] {
        (try? await api.discoverChannels(query: query).channels) ?? []
    }

    func subscribeChannel(chatId: String) async -> Chat? {
        do {
            let chat = try await api.subscribe(chatId: chatId).chat
            await loadChats(silent: true)
            return chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func unsubscribeChannel(chatId: String) async {
        do {
            try await api.unsubscribe(chatId: chatId)
            chats.removeAll { $0.id == chatId }
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: - Privacy & profile

    func updateProfile(_ fields: [String: Any]) async -> Bool {
        do {
            let user = try await api.patchProfile(fields).user
            me = user
            return true
        } catch {
            toast = error.localizedDescription
            return false
        }
    }

    func refreshMe() async {
        if let user = try? await api.me().user {
            me = user
        }
    }

    func loadSessions() async -> [SessionInfo] {
        (try? await api.sessions().sessions) ?? []
    }

    func revokeSession(_ id: String) async {
        try? await api.revokeSession(id: id)
    }

    func revokeOtherSessions() async {
        try? await api.revokeOtherSessions()
    }

    func loadBlocks() async -> [User] {
        (try? await api.blocks().users) ?? []
    }

    func blockUser(_ userId: String) async {
        do {
            try await api.setBlock(userId: userId, blocked: true)
            toast = "已加入黑名单"
        } catch {
            toast = error.localizedDescription
        }
    }

    func unblockUser(_ userId: String) async {
        do {
            try await api.setBlock(userId: userId, blocked: false)
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: - Chat management

    func loadFolders() async {
        if let response = try? await api.folders() {
            folders = response.folders
        }
    }

    func createFolder(_ name: String) async -> Folder? {
        do {
            let folder = try await api.createFolder(name: name).folder
            folders.append(folder)
            return folder
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func deleteFolder(_ id: String) async {
        try? await api.deleteFolder(id: id)
        folders.removeAll { $0.id == id }
        for index in chats.indices where chats[index].folderId == id {
            chats[index].folderId = nil
        }
    }

    func assignFolder(chatId: String, folderId: String?) async {
        do {
            try await api.assignFolder(chatId: chatId, folderId: folderId)
            if let index = chats.firstIndex(where: { $0.id == chatId }) {
                chats[index].folderId = folderId
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func batchChats(_ action: String, chatIds: [String]) async {
        do {
            try await api.batchChats(action, chatIds: chatIds)
            switch action {
            case "pin":
                for index in chats.indices where chatIds.contains(chats[index].id) { chats[index].pinned = true }
            case "unpin":
                for index in chats.indices where chatIds.contains(chats[index].id) { chats[index].pinned = false }
            case "archive":
                for index in chats.indices where chatIds.contains(chats[index].id) { chats[index].archived = true }
            case "unarchive":
                for index in chats.indices where chatIds.contains(chats[index].id) { chats[index].archived = false }
            case "read":
                await loadChats(silent: true)
            case "delete":
                chats.removeAll { chatIds.contains($0.id) }
            default:
                break
            }
            sortChats()
        } catch {
            toast = error.localizedDescription
        }
    }

    func setWallpaper(chatId: String, wallpaper: String?) async {
        do {
            try await api.setWallpaper(chatId: chatId, wallpaper: wallpaper)
            if let index = chats.firstIndex(where: { $0.id == chatId }) {
                chats[index].wallpaper = wallpaper
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func openSavedChat() async -> Chat? {
        do {
            let chat = try await api.savedChat().chat
            await loadChats(silent: true)
            return chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func globalSearch(_ query: String, kind: String) async -> [Message] {
        do {
            return try await api.globalSearch(query: query, kind: kind).messages
        } catch {
            toast = error.localizedDescription
            return []
        }
    }

    func sortChats() {
        chats.sort { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return (lhs.lastMessage?.seq ?? 0) > (rhs.lastMessage?.seq ?? 0)
        }
    }

    // MARK: - Polls, topics, reports

    func createPoll(chatId: String, question: String, options: [String], multiple: Bool, topicId: String?) async {
        do {
            let response = try await api.createPoll(
                chatId: chatId,
                question: question,
                options: options,
                multiple: multiple,
                topicId: topicId
            )
            messages[chatId] = merge(messages[chatId] ?? [], [response.message])
        } catch {
            toast = error.localizedDescription
        }
    }

    func votePoll(chatId: String, pollId: String, optionIndex: Int) async {
        do {
            let response = try await api.votePoll(chatId: chatId, pollId: pollId, optionIndex: optionIndex)
            if var list = messages[chatId] {
                for index in list.indices where list[index].poll?.id == pollId {
                    list[index].poll = response.poll
                }
                messages[chatId] = list
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    func reportMessage(chatId: String, seq: Int64, reason: String) async {
        do {
            try await api.reportMessage(chatId: chatId, seq: seq, reason: reason)
            toast = "已举报，管理员会处理"
        } catch {
            toast = error.localizedDescription
        }
    }

    func loadReports(chatId: String) async -> [ReportItem] {
        do {
            return try await api.reports(chatId: chatId).reports
        } catch {
            toast = error.localizedDescription
            return []
        }
    }

    func loadTopics(chatId: String) async -> [Topic] {
        do {
            return try await api.topics(chatId: chatId).topics
        } catch {
            return []
        }
    }

    func createTopic(chatId: String, title: String) async -> Topic? {
        do {
            let topic = try await api.createTopic(chatId: chatId, title: title).topic
            toast = "话题已创建"
            return topic
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func loadTopic(chatId: String, topicId: String) async {
        guard let response = try? await api.messages(chatId: chatId, limit: 60, topicId: topicId) else { return }
        messages[chatId] = merge(messages[chatId] ?? [], response.messages)
    }

    // MARK: - Groups

    func createGroup(title: String, memberIds: [String]) async -> Chat? {
        do {
            let response = try await api.createGroup(title: title, memberIds: memberIds)
            await loadChats(silent: true)
            return response.chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func updateChat(chatId: String, fields: [String: Any]) async {
        do {
            let response = try await api.updateChat(chatId: chatId, fields: fields)
            replaceChat(response.chat)
        } catch {
            toast = error.localizedDescription
        }
    }

    func addGroupMember(chatId: String, userId: String) async {
        do {
            let response = try await api.addMember(chatId: chatId, userId: userId)
            replaceChat(response.chat)
        } catch {
            toast = error.localizedDescription
        }
    }

    func removeGroupMember(chatId: String, userId: String) async {
        do {
            try await api.removeMember(chatId: chatId, userId: userId)
            await loadChats(silent: true)
        } catch {
            toast = error.localizedDescription
        }
    }

    func setGroupRole(chatId: String, userId: String, role: String) async {
        do {
            let response = try await api.setMemberRole(chatId: chatId, userId: userId, role: role)
            replaceChat(response.chat)
        } catch {
            toast = error.localizedDescription
        }
    }

    func muteGroupMember(chatId: String, userId: String, muted: Bool) async {
        do {
            let until = muted ? Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000 * 365 : 0
            let response = try await api.muteMember(chatId: chatId, userId: userId, until: until)
            replaceChat(response.chat)
        } catch {
            toast = error.localizedDescription
        }
    }

    func createGroupInvite(chatId: String) async -> String? {
        do {
            let response = try await api.createInvite(chatId: chatId)
            return response.link
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func leaveGroup(chatId: String) async {
        do {
            try await api.leaveChat(chatId: chatId)
            chats.removeAll { $0.id == chatId }
            messages[chatId] = nil
        } catch {
            toast = error.localizedDescription
        }
    }

    func dissolveGroup(chatId: String) async {
        do {
            try await api.dissolveChat(chatId: chatId)
            chats.removeAll { $0.id == chatId }
            messages[chatId] = nil
        } catch {
            toast = error.localizedDescription
        }
    }

    func joinByInvite(code: String) async -> Chat? {
        do {
            let response = try await api.joinChat(code: code)
            await loadChats(silent: true)
            return response.chat
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func replaceChat(_ chat: Chat) {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[index] = chat
        } else {
            chats.append(chat)
        }
    }

    func chat(byId id: String) -> Chat? {
        chats.first { $0.id == id }
    }

    func searchMessages(chatId: String, query: String) async -> [Message] {
        do {
            return try await api.searchMessages(chatId: chatId, query: query).messages
        } catch {
            toast = error.localizedDescription
            return []
        }
    }

    func loadOlder(chatId: String) async {
        guard !loadingOlder, hasMore[chatId] != false else { return }
        guard let oldest = messages[chatId]?.first(where: { $0.seq > 0 })?.seq else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        if let response = try? await api.messages(chatId: chatId, before: oldest, limit: 50) {
            messages[chatId] = merge(messages[chatId] ?? [], response.messages)
            hasMore[chatId] = response.hasMore
        }
    }

    private func replaceMessage(chatId: String, message: Message) {
        guard var list = messages[chatId], let index = list.firstIndex(where: { $0.seq == message.seq }) else {
            messages[chatId] = merge(messages[chatId] ?? [], [message])
            return
        }
        list[index] = message
        messages[chatId] = list
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
        realtime.onEdit = { [weak self] message in
            Task { @MainActor in
                self?.replaceMessage(chatId: chatId, message: message)
            }
        }
        realtime.onDelete = { [weak self] seq in
            Task { @MainActor in
                guard let self = self, var list = self.messages[chatId],
                      let index = list.firstIndex(where: { $0.seq == seq }) else { return }
                list[index].deleted = true
                list[index].text = ""
                list[index].media = nil
                self.messages[chatId] = list
            }
        }
        realtime.onReaction = { [weak self] seq, reactions in
            Task { @MainActor in
                guard let self = self, var list = self.messages[chatId],
                      let index = list.firstIndex(where: { $0.seq == seq }) else { return }
                list[index].reactions = reactions
                self.messages[chatId] = list
            }
        }
        CallService.shared.realtime = realtime
        realtime.onSignal = { payload in
            CallService.shared.handleSignal(payload)
        }
        realtime.onPoll = { [weak self] seq, poll in
            Task { @MainActor in
                guard let self = self, var list = self.messages[chatId],
                      let index = list.firstIndex(where: { $0.seq == seq }) else { return }
                list[index].poll = poll
                self.messages[chatId] = list
            }
        }
        realtime.onPin = { [weak self] seq, pinned in
            Task { @MainActor in
                guard let self = self, var list = self.messages[chatId],
                      let index = list.firstIndex(where: { $0.seq == seq }) else { return }
                list[index].pinned = pinned
                self.messages[chatId] = list
            }
        }
        realtime.connect(baseURL: baseURL, chatId: chatId, token: token)
    }

    // MARK: - Media

    struct PendingUpload: Equatable {
        let fileURL: URL
        let kind: String
        let mime: String
        let name: String
        let caption: String
        let width: Int?
        let height: Int?
        let durationMs: Int?
        let chatId: String
    }

    func sendMedia(
        chatId: String,
        fileURL: URL,
        kind: String,
        mime: String,
        name: String,
        caption: String = "",
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil
    ) {
        let job = PendingUpload(
            fileURL: fileURL,
            kind: kind,
            mime: mime,
            name: name,
            caption: caption,
            width: width,
            height: height,
            durationMs: durationMs,
            chatId: chatId
        )
        pendingUpload = job
        startUpload(job)
    }

    func retryUpload() {
        guard let job = pendingUpload else { return }
        startUpload(job)
    }

    func cancelUpload() {
        uploadTask?.cancel()
        uploadTask = nil
        pendingUpload = nil
        uploadProgress = nil
        uploadName = nil
        uploadFailed = false
    }

    private func startUpload(_ job: PendingUpload) {
        uploadTask?.cancel()
        uploadFailed = false
        uploadName = job.name
        uploadProgress = 0

        uploadTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                let media = try await self.api.uploadMedia(
                    chatId: job.chatId,
                    fileURL: job.fileURL,
                    kind: job.kind,
                    mime: job.mime,
                    name: job.name,
                    width: job.width,
                    height: job.height,
                    durationMs: job.durationMs,
                    progress: { value in
                        Task { @MainActor in
                            self.uploadProgress = value
                        }
                    }
                )
                let clientId = UUID().uuidString
                let response = try await self.api.sendMessage(
                    chatId: job.chatId,
                    text: job.caption,
                    clientId: clientId,
                    mediaId: media.id
                )
                self.messages[job.chatId] = self.merge(self.messages[job.chatId] ?? [], [response.message])
                await self.loadChats(silent: true)
                self.uploadProgress = nil
                self.uploadName = nil
                self.pendingUpload = nil
            } catch {
                if Task.isCancelled { return }
                self.uploadFailed = true
                self.toast = error.localizedDescription
            }
        }
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
