import SwiftUI

struct ChatView: View {
    let chat: Chat

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var viewingImage: Media?
    @State private var viewingVideo: Media?

    private var messages: [Message] { app.messages[chat.id] ?? [] }
    private var myId: String? { app.me?.id }
    private var peer: User? { chat.peer(myId: myId) }

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
            header(c)

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
                                    bubble(index: index, message: message, colors: c)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .onChange(of: messages.last?.id) { newValue in
                            guard let id = newValue else { return }
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                        .onAppear {
                            if let id = messages.last?.id {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            ChatComposer(chatId: chat.id, draft: $draft)
        }
        .sheet(item: $viewingImage) { media in
            ImageViewerSheet(media: media, token: app.token)
        }
        .sheet(item: $viewingVideo) { media in
            VideoPlayerSheet(media: media, token: app.token)
        }
        .background(c.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            Task { await app.openChat(chat.id) }
        }
        .onDisappear {
            app.closeChat()
        }
    }

    private func bubble(index: Int, message: Message, colors c: TgColors) -> some View {
        let older = index > 0 ? messages[index - 1] : nil
        let newer = index + 1 < messages.count ? messages[index + 1] : nil
        let dateChanged = older == nil || !isSameDay(older!.createdAt, message.createdAt)
        let isOut = message.senderId == myId
        let showAuthor = !isOut && chat.isGroup &&
            (newer == nil || newer!.senderId != message.senderId || !isSameDay(newer!.createdAt, message.createdAt))
        let readByPeer = isOut && message.seq > 0 && chat.otherReadSeq >= message.seq

        return VStack(spacing: 0) {
            if dateChanged {
                DateChipView(label: formatDateHeader(message.createdAt), colors: c)
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
                .padding(.vertical, 1.5)
                .id(message.id)
            } else {
                MessageBubbleView(
                    message: message,
                    isOut: isOut,
                    showAuthor: showAuthor,
                    readByPeer: readByPeer,
                    colors: c
                )
                .id(message.id)
            }
        }
    }

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

}
