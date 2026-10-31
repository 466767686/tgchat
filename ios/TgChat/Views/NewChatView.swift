import SwiftUI

struct NewChatView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let onOpen: (Chat) -> Void

    @State private var query = ""
    @State private var showGroupCreate = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section {
                    Button {
                        showGroupCreate = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(c.accent.opacity(0.15)).frame(width: 46, height: 46)
                                Image(systemName: "person.3.fill").foregroundColor(c.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("新建群组").font(.system(size: 16, weight: .medium)).foregroundColor(c.textPrimary)
                                Text("选择成员，创建群聊").font(.system(size: 12)).foregroundColor(c.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(c.textTertiary)
                        }
                    }
                    .listRowBackground(c.background)
                }

                if app.usersDirectory.isEmpty {
                    Text("没有找到联系人，请联系管理员创建账号")
                        .font(.system(size: 14))
                        .foregroundColor(c.textTertiary)
                        .listRowBackground(c.background)
                } else {
                    ForEach(app.usersDirectory) { user in
                        Button {
                            Task {
                                if let chat = await app.startChat(with: user.id) {
                                    onOpen(chat)
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(name: user.title, colorHex: user.avatarColor, size: 46)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.title)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(c.textPrimary)
                                    Text("@\(user.username)")
                                        .font(.system(size: 13))
                                        .foregroundColor(c.textSecondary)
                                }
                                Spacer()
                                if user.role == "admin" {
                                    Text("管理员")
                                        .font(.system(size: 11))
                                        .foregroundColor(c.accent)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(c.accent.opacity(0.12)))
                                }
                            }
                        }
                        .listRowBackground(c.background)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索用户名或昵称")
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showGroupCreate) {
                GroupCreateView { chat in
                    onOpen(chat)
                    dismiss()
                }
                .environmentObject(app)
            }
            .task {
                await app.loadUsers(query: "")
            }
            .task(id: query) {
                if !query.isEmpty {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                await app.loadUsers(query: query)
            }
        }
    }
}
