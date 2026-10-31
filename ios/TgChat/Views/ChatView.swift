import SwiftUI
import UIKit

struct ChatView: View {
    let chat: Chat

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
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

    private var messages: [Message] { app.messages[chat.id] ?? [] }
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

            messagesArea(c)

            if selectionMode {
                selectionBar(c)
            } else {
                ChatComposer(chatId: chat.id, draft: $draft, replyTarget: $replyTarget, editing: $editing)
            }
        }
        .background(c.background.ignoresSafeArea())
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
            Task { await app.openChat(chat.id) }
        }
        .onDisappear {
            app.closeChat()
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

            AvatarView(name: chat.displayTitle(myId: myId), colorHex: chat.avatarColor(myId: myId), size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(chat.displayTitle(myId: myId))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(c.textPrimary)
                    .lineLimit(1)
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundColor(app.typingName != nil ? c.accent : c.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(c.textSecondary)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(c.header)
    }

    private var statusText: String {
        if let typing = app.typingName {
            return "\(typing) 正在输入…"
        }
        if chat.isGroup {
            return "\(chat.members.count) 位成员"
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

    private func messagesArea(_ c: TgColors) -> some View {
        ZStack {
            LinearGradient(colors: [c.chatBgTop, c.chatBgBottom], startPoint: .top, endPoint: .bottom)
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
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onChange(of: messages.last?.id) { _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.seq, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: jumpToSeq) { seq in
                        guard let seq = seq else { return }
                        withAnimation {
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

                if let media = message.media {
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
                .buttonStyle(.plain)
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

        if message.senderId == myId && !message.deleted {
            Button(role: .destructive) {
                Task { await app.deleteMessage(chatId: chat.id, seq: message.seq) }
            } label: {
                Label("删除", systemImage: "trash")
            }
        }

        Button {
            selectionMode = true
            selected = [message.seq]
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
