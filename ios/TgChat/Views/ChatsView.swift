import SwiftUI

struct ChatsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var path = NavigationPath()
    @State private var showNewChat = false
    @State private var showSettings = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header(c)

                if app.chatsLoading && app.chats.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if app.chats.isEmpty {
                    EmptyStateView(
                        title: "还没有会话",
                        subtitle: "点右上角的按钮开始聊天",
                        colors: c
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(app.chats) { chat in
                                NavigationLink(value: chat) {
                                    ChatRowView(chat: chat, myId: app.me?.id, colors: c)
                                }
                                .buttonStyle(.plain)

                                Divider()
                                    .padding(.leading, 78)
                            }
                        }
                    }
                }
            }
            .background(c.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Chat.self) { chat in
                ChatView(chat: chat)
            }
        }
        .sheet(isPresented: $showNewChat) {
            NewChatView { chat in
                showNewChat = false
                path.append(chat)
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(app)
        }
    }

    private func header(_ c: TgColors) -> some View {
        HStack(spacing: 12) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(c.textSecondary)
            }

            Text("Chats")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(c.textPrimary)

            Spacer()

            Button {
                showNewChat = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(c.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(c.background)
    }
}

struct ChatRowView: View {
    let chat: Chat
    let myId: String?
    let colors: TgColors

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: chat.displayTitle(myId: myId), colorHex: chat.avatarColor(myId: myId), size: 54)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.displayTitle(myId: myId))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(formatListTime(chat.lastMessage?.createdAt ?? chat.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(chat.unread > 0 ? colors.accent : colors.textTertiary)
                }

                HStack(spacing: 8) {
                    Text(chat.preview(myId: myId))
                        .font(.system(size: 14))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    if chat.unread > 0 {
                        Text(chat.unread > 99 ? "99+" : "\(chat.unread)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(colors.accent))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}
