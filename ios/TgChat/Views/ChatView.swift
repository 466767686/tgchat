import SwiftUI
import UIKit

struct ChatView: View {
    let chat: Chat

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var viewingImage: Media?
    @State private var viewingVideo: Media?
    @State private var replyTarget: Message?
    @State private var editing: Message?
    @State private var selectionMode = false
    @State private var selected: Set<Int64> = []
    @State private var forwarding: Message?
    @State private var showForwardPicker = false
    @State private var showSearch = false
    @State private var jumpToSeq: Int64?
    @State private var showGroupInfo = false
    @State private var topics: [Topic] = []
    @State private var selectedTopic: Topic?
    @State private var showPollCreate = false
    @State private var showTopicCreate = false
    @State private var newTopicTitle = ""
    @State private var reportTarget: Message?
    @State private var showCall = false
    @State private var discussionChat: Chat?

    private var allMessages: [Message] { app.messages[chat.id] ?? [] }
    private var messages: [Message] {
        guard liveChat.topicsEnabled == true else { return allMessages }
        if let selected = selectedTopic {
            return allMessages.filter { $0.topicId == selected.id }
        }
        return allMessages.filter { $0.topicId == nil }
    }
    private var liveChat: Chat { app.chat(byId: chat.id) ?? chat }
    private var me: User? { liveChat.members.first { $0.id == myId } }
    private var muted: Bool { me?.isMuted == true }
    private var myId: String? { app.me?.id }
    private var pinnedMessage: Message? { messages.last(where: { $0.pinned && !$0.deleted }) }

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
            if selectionMode {
                selectionHeader(c)
            } else {
                header(c)
            }

            if let pinned = pinnedMessage, !selectionMode {
                pinnedBanner(pinned, c)
            }

            if liveChat.topicsEnabled == true, !selectionMode {
                topicsBar(c)
            }

            messagesArea(c)

            if selectionMode {
                selectionBar(c)
            } else if liveChat.isChannel && !liveChat.canManage {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill").font(.system(size: 11))
                    Text("频道仅管理员可发布").font(.system(size: 12))
                }
                .foregroundColor(c.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(c.header)
            } else {
                if muted {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.slash.fill").font(.system(size: 11))
                        Text("你已被禁言，无法发送消息").font(.system(size: 12))
                    }
                    .foregroundColor(c.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(c.surfaceAlt)
                }
                ChatComposer(
                    chatId: chat.id,
                    draft: $draft,
                    replyTarget: $replyTarget,
                    editing: $editing,
                    mentionUsers: liveChat.isGroup ? liveChat.members.filter { $0.id != myId } : [],
                    topicId: liveChat.topicsEnabled == true ? selectedTopic?.id : nil,
                    allowPoll: liveChat.isGroup,
                    onCreatePoll: { showPollCreate = true }
                )
            }
        }
        .background(c.background.ignoresSafeArea())
        .animation(Motion.animation(Motion.standard, reduceMotion: reduceMotion), value: selectionMode)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $viewingImage) {
            ImageViewerSheet(media: $0, token: app.token)
        }
        .sheet(item: $viewingVideo) {
            VideoPlayerSheet(media: $0, token: app.token)
        }
        .sheet(isPresented: $showSearch) {
            ChatSearchView(chatId: chat.id, title: chat.displayTitle(myId: myId)) { seq in
                showSearch = false
                jumpToSeq = seq
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showPollCreate) {
            PollCreateView(chatId: chat.id, topicId: selectedTopic?.id)
                .environmentObject(app)
        }
        .alert("新建话题", isPresented: $showTopicCreate) {
            TextField("话题名称", text: $newTopicTitle)
            Button("创建") {
                let title = newTopicTitle.trimmingCharacters(in: .whitespaces)
                newTopicTitle = ""
                guard !title.isEmpty else { return }
                Task {
                    if let topic = await app.createTopic(chatId: chat.id, title: title) {
                        topics = await app.loadTopics(chatId: chat.id)
                        selectedTopic = topic
                        await app.loadTopic(chatId: chat.id, topicId: topic.id)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("举报原因", isPresented: Binding(
            get: { reportTarget != nil },
            set: { if !$0 { reportTarget = nil } }
        ), titleVisibility: .visible) {
            ForEach(["垃圾信息", "骚扰", "诈骗", "其他"], id: \.self) { reason in
                Button(reason) {
                    if let target = reportTarget {
                        Task { await app.reportMessage(chatId: chat.id, seq: target.seq, reason: reason) }
                    }
                    reportTarget = nil
                }
            }
            Button("取消", role: .cancel) { reportTarget = nil }
        }
        .sheet(isPresented: $showGroupInfo) {
            GroupInfoView(chatId: chat.id)
                .environmentObject(app)
        }
        .sheet(isPresented: $showForwardPicker) {
            ForwardPickerView { target in
                showForwardPicker = false
                if let message = forwarding {
                    Task {
                        await app.sendMessage(
                            message.text,
                            chatId: target.id,
                            forwardedFrom: message.senderName
                        )
                    }
                }
            }
            .environmentObject(app)
        }
        .onAppear {
            Task {
                await app.openChat(chat.id)
                await app.refreshChat(chat.id)
                if liveChat.topicsEnabled == true {
                    topics = await app.loadTopics(chatId: chat.id)
                }
            }
        }
        .onDisappear {
            app.closeChat()
        }
        .onReceive(CallService.shared.$state) { state in
            if state.isBusy { showCall = true }
        }
        .sheet(item: $discussionChat) { chat in
            NavigationStack {
                ChatView(chat: chat)
            }
        }
        .sheet(isPresented: $showCall, onDismiss: {
            if !CallService.shared.state.isBusy {
                CallService.shared.reset()
            }
        }) {
            CallView()
        }
    }

    // MARK: - Header

    private func header(_ c: TgColors) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(c.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(MotionIconPressStyle())

            Button {
                if liveChat.isGroup || liveChat.isChannel { showGroupInfo = true }
            } label: {
                HStack(spacing: 10) {
                    AvatarView(
                        name: liveChat.displayTitle(myId: myId),
                        colorHex: liveChat.avatarColor(myId: myId),
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(liveChat.displayTitle(myId: myId))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(c.textPrimary)
                            .lineLimit(1)
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundColor(app.typingName != nil ? c.accent : c.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(MotionPressStyle(scale: 0.97))

            Spacer()

            if !liveChat.isGroup && !liveChat.isSaved {
                Button {
                    CallService.shared.startCall(
                        chatId: chat.id,
                        peerName: liveChat.displayTitle(myId: myId)
                    )
                    showCall = true
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(c.accent)
                        .frame(width: 32, height: 32)
                }

                Button {
                    CallService.shared.startCall(
                        chatId: chat.id,
                        peerName: liveChat.displayTitle(myId: myId),
                        video: true
                    )
                    showCall = true
                } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(c.accent)
                        .frame(width: 32, height: 32)
                }
            }

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(c.textSecondary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(MotionIconPressStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(c.header)
    }

    private var statusText: String {
        if let typing = app.typingName {
            return "\(typing) 正在输入…"
        }
        if liveChat.isChannel {
            return "\(liveChat.subscriberCount ?? liveChat.members.count) 位订阅者"
        }
        if liveChat.isGroup {
            return "\(liveChat.members.count) 位成员"
        }
        return "最近在线"
    }

    private func pinnedBanner(_ message: Message, _ c: TgColors) -> some View {
        Button {
            jumpToSeq = message.seq
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12))
                    .foregroundColor(c.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("置顶消息")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(c.accent)
                    Text(message.deleted ? "消息已删除" : (message.text.isEmpty ? "媒体消息" : message.text))
                        .font(.system(size: 12))
                        .foregroundColor(c.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(c.surfaceAlt)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages

    private func topicsBar(_ c: TgColors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                topicChip(title: "大厅", emoji: nil, active: selectedTopic == nil, colors: c) {
                    selectedTopic = nil
                }
                ForEach(topics) { topic in
                    topicChip(
                        title: topic.title,
                        emoji: topic.emoji,
                        active: selectedTopic?.id == topic.id,
                        colors: c
                    ) {
                        selectedTopic = topic
                        Task { await app.loadTopic(chatId: chat.id, topicId: topic.id) }
                    }
                }
                if liveChat.canManage {
                    Button {
                        showTopicCreate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(c.accent)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(c.header)
    }

    private func topicChip(title: String, emoji: String?, active: Bool, colors c: TgColors, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let emoji = emoji { Text(emoji).font(.system(size: 12)) }
                Text(title)
                    .font(.system(size: 12, weight: active ? .semibold : .regular))
            }
            .foregroundColor(active ? .white : c.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(active ? c.accent : c.surfaceAlt))
        }
        .buttonStyle(.plain)
    }

    private func messagesArea(_ c: TgColors) -> some View {
        ZStack {
            wallpaperColors(liveChat.wallpaper).0
                .opacity(scheme == .dark && liveChat.wallpaper != nil ? 0.55 : 1)
                .ignoresSafeArea()

            if messages.isEmpty {
                Text("发送第一条消息，开始对话")
                    .font(.system(size: 14))
                    .foregroundColor(c.textSecondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                                messageRow(index: index, message: message, colors: c)
                                    .id(message.seq)
                                    .transition(.motionMessage(reduceMotion: reduceMotion))
                            }
                        }
                        .padding(.vertical, 8)
                        .animation(
                            Motion.animation(Motion.standard, reduceMotion: reduceMotion),
                            value: messages.last?.seq
                        )
                    }
                    .onChange(of: messages.last?.id) { _ in
                        if let last = messages.last {
                            withAnimation(reduceMotion ? nil : Motion.standard) {
                                proxy.scrollTo(last.seq, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: jumpToSeq) { seq in
                        guard let seq = seq else { return }
                        withAnimation(reduceMotion ? nil : Motion.gentle) {
                            proxy.scrollTo(seq, anchor: .center)
                        }
                        jumpToSeq = nil
                    }
                    .onAppear {
                        if let last = messages.last {
                            proxy.scrollTo(last.seq, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(index: Int, message: Message, colors c: TgColors) -> some View {
        let older = index > 0 ? messages[index - 1] : nil
        let newer = index + 1 < messages.count ? messages[index + 1] : nil
        let dateChanged = older == nil || !isSameDay(older!.createdAt, message.createdAt)
        let isOut = message.senderId == myId
        let showAuthor = !isOut && chat.isGroup &&
            (newer == nil || newer!.senderId != message.senderId || !isSameDay(newer!.createdAt, message.createdAt))
        let readByPeer = isOut && message.seq > 0 && chat.otherReadSeq >= message.seq
        let isSelected = selected.contains(message.seq)

        VStack(spacing: 0) {
            if dateChanged {
                DateChipView(label: formatDateHeader(message.createdAt), colors: c)
            }

            HStack(alignment: .center, spacing: 6) {
                if selectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? c.accent : c.textTertiary)
                        .padding(.leading, 10)
                }

                if let poll = message.poll {
                    HStack {
                        if isOut { Spacer(minLength: 44) }
                        PollMessageView(message: message, poll: poll, colors: c)
                        if !isOut { Spacer(minLength: 44) }
                    }
                    .padding(.horizontal, 10)
                } else if let media = message.media {
                    HStack {
                        if isOut { Spacer(minLength: 44) }
                        MediaMessageView(
                            message: message,
                            media: media,
                            isOut: isOut,
                            readByPeer: readByPeer,
                            colors: c,
                            token: app.token,
                            onOpenImage: { viewingImage = $0 },
                            onOpenVideo: { viewingVideo = $0 }
                        )
                        if !isOut { Spacer(minLength: 44) }
                    }
                    .padding(.horizontal, 10)
                } else {
                    MessageBubbleView(
                        message: message,
                        isOut: isOut,
                        showAuthor: showAuthor,
                        readByPeer: readByPeer,
                        colors: c
                    )
                }
            }
            .padding(.vertical, 1.5)

            if !message.reactions.isEmpty {
                reactionsRow(message, c)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectionMode {
                toggleSelection(message)
            }
        }
        .contextMenu {
            menuItems(message)
        }
        .onAppear {
            if index == 0 {
                Task { await app.loadOlder(chatId: chat.id) }
            }
        }
    }

    private func reactionsRow(_ message: Message, _ c: TgColors) -> some View {
        HStack(spacing: 4) {
            ForEach(message.reactions, id: \.emoji) { reaction in
                Button {
                    Task { await app.toggleReaction(chatId: chat.id, seq: message.seq, emoji: reaction.emoji) }
                } label: {
                    Text("\(reaction.emoji) \(reaction.count)")
                        .font(.system(size: 11))
                        .foregroundColor(c.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(reaction.me ? c.accent.opacity(0.18) : c.surfaceAlt))
                }
                .buttonStyle(MotionPressStyle(scale: 0.9))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 3)
    }

    @ViewBuilder
    private func menuItems(_ message: Message) -> some View {
        Button {
            replyTarget = message
            editing = nil
        } label: {
            Label("回复", systemImage: "arrowshape.turn.up.left")
        }

        Button {
            UIPasteboard.general.string = message.text
        } label: {
            Label("复制", systemImage: "doc.on.doc")
        }

        Button {
            forwarding = message
            showForwardPicker = true
        } label: {
            Label("转发", systemImage: "arrowshape.turn.up.right")
        }

        Button {
            Task { await app.pinMessage(chatId: chat.id, seq: message.seq, pinned: !message.pinned) }
        } label: {
            Label(message.pinned ? "取消置顶" : "置顶", systemImage: "pin")
        }

        Menu {
            ForEach(["👍", "❤️", "😂", "😮", "😢", "🔥"], id: \.self) { emoji in
                Button(emoji) {
                    Task { await app.toggleReaction(chatId: chat.id, seq: message.seq, emoji: emoji) }
                }
            }
        } label: {
            Label("回应", systemImage: "face.smiling")
        }

        if message.senderId == myId && !message.deleted && message.media == nil {
            Button {
                editing = message
                draft = message.text
                replyTarget = nil
            } label: {
                Label("编辑", systemImage: "pencil")
            }
        }

        if message.senderId != myId && !message.deleted {
            Button {
                reportTarget = message
            } label: {
                Label("举报", systemImage: "exclamationmark.bubble")
            }
            if !liveChat.isGroup && !liveChat.isChannel {
                Button(role: .destructive) {
                    Task { await app.blockUser(message.senderId) }
                } label: {
                    Label("屏蔽用户", systemImage: "hand.raised")
                }
            }
        }

        if (message.senderId == myId || liveChat.canManage) && !message.deleted {
            Button(role: .destructive) {
                Task { await app.deleteMessage(chatId: chat.id, seq: message.seq) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }

        if liveChat.isChannel, let discussion = liveChat.discussionChatId,
           let chat = app.chat(byId: discussion) {
            Button {
                discussionChat = chat
            } label: {
                Label("评论", systemImage: "bubble.left.and.bubble.right")
            }
        }

        Button {
            Haptics.selection()
            withAnimation(Motion.animation(Motion.standard, reduceMotion: reduceMotion)) {
                selectionMode = true
                selected = [message.seq]
            }
        } label: {
            Label("多选", systemImage: "checkmark.circle")
        }
    }

    // MARK: - Selection

    private func selectionHeader(_ c: TgColors) -> some View {
        HStack(spacing: 12) {
            Button {
                selectionMode = false
                selected.removeAll()
            } label: {
                Text("取消")
                    .font(.system(size: 15))
                    .foregroundColor(c.accent)
            }
            Text("已选择 \(selected.count) 条")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(c.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(c.header)
        .transition(.opacity)
    }

    private func selectionBar(_ c: TgColors) -> some View {
        HStack(spacing: 28) {
            Button {
                let items = messages.filter { selected.contains($0.seq) }
                UIPasteboard.general.string = items.map { $0.text }.joined(separator: "\n")
                selectionMode = false
                selected.removeAll()
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.doc")
                    Text("复制").font(.system(size: 11))
                }
                .foregroundColor(c.textSecondary)
            }

            Button {
                if let first = messages.first(where: { selected.contains($0.seq) }) {
                    forwarding = first
                    showForwardPicker = true
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.right")
                    Text("转发").font(.system(size: 11))
                }
                .foregroundColor(c.textSecondary)
            }

            Button {
                Task {
                    for seq in selected {
                        await app.deleteMessage(chatId: chat.id, seq: seq)
                    }
                    selectionMode = false
                    selected.removeAll()
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "trash")
                    Text("删除").font(.system(size: 11))
                }
                .foregroundColor(c.danger)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(c.header)
        .transition(.opacity)
    }

    private func toggleSelection(_ message: Message) {
        if selected.contains(message.seq) {
            selected.remove(message.seq)
        } else {
            selected.insert(message.seq)
        }
    }
}

// MARK: - Search

struct ChatSearchView: View {
    let chatId: String
    let title: String
    let onSelect: (Int64) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var results: [Message] = []
    @State private var searching = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(c.textTertiary)
                    TextField("搜索聊天记录", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(c.textTertiary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(c.surfaceAlt))
                .padding(12)

                if searching {
                    ProgressView().padding()
                }

                List {
                    ForEach(results) { message in
                        Button {
                            onSelect(message.seq)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(message.senderName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(c.accent)
                                    Spacer()
                                    Text(formatDateHeader(message.createdAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(c.textTertiary)
                                }
                                Text(message.text.isEmpty ? "媒体消息" : message.text)
                                    .font(.system(size: 14))
                                    .foregroundColor(c.textPrimary)
                                    .lineLimit(2)
                            }
                        }
                        .listRowBackground(c.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(c.background.ignoresSafeArea())
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searching = true
        results = await app.searchMessages(chatId: chatId, query: text)
        searching = false
    }
}

// MARK: - Forward picker

struct ForwardPickerView: View {
    let onSelect: (Chat) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List(app.chats) { chat in
                Button {
                    onSelect(chat)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(
                            name: chat.displayTitle(myId: app.me?.id),
                            colorHex: chat.avatarColor(myId: app.me?.id),
                            size: 42
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(chat.displayTitle(myId: app.me?.id))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(c.textPrimary)
                            Text(chat.preview(myId: app.me?.id))
                                .font(.system(size: 12))
                                .foregroundColor(c.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowBackground(c.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("转发到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
