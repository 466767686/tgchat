import SwiftUI

struct ChannelCreateView: View {
    let onCreated: (Chat) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var title = ""
    @State private var username = ""
    @State private var description = ""
    @State private var isPublic = true
    @State private var creating = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section("频道信息") {
                    TextField("频道名称", text: $title)
                        .listRowBackground(c.background)
                    TextField("简介（可选）", text: $description, axis: .vertical)
                        .lineLimit(1...3)
                        .listRowBackground(c.background)
                }

                Section {
                    Toggle("公开频道", isOn: $isPublic)
                        .listRowBackground(c.background)
                    if isPublic {
                        HStack {
                            Text("@").foregroundColor(c.textTertiary)
                            TextField("用户名（4-32 位小写字母/数字/下划线）", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .listRowBackground(c.background)
                    }
                } footer: {
                    Text(isPublic ? "公开频道可通过 @用户名 被发现和订阅" : "私有频道只能通过邀请链接加入")
                        .font(.system(size: 12))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("新建频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || creating)
                }
            }
        }
    }

    private func create() {
        creating = true
        Task {
            let name = title.trimmingCharacters(in: .whitespaces)
            let handle = username.trimmingCharacters(in: .whitespaces).lowercased()
            if let chat = await app.createChannel(
                title: name,
                username: isPublic && !handle.isEmpty ? handle : nil,
                description: description.trimmingCharacters(in: .whitespaces)
            ) {
                onCreated(chat)
                dismiss()
            }
            creating = false
        }
    }
}

struct ChannelDiscoverView: View {
    let onOpen: (Chat) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var channels: [ChannelSummary] = []
    @State private var loading = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(c.textTertiary)
                    TextField("搜索频道名称或 @用户名", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(c.surfaceAlt))
                .padding(12)

                if loading {
                    ProgressView().padding()
                }

                List(channels) { channel in
                    HStack(spacing: 12) {
                        AvatarView(name: channel.title, colorHex: "#E0A040", size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(channel.title)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(c.textPrimary)
                            Text("@\(channel.username ?? "") · \(channel.subscriberCount) 订阅者")
                                .font(.system(size: 12))
                                .foregroundColor(c.textSecondary)
                        }
                        Spacer()
                        if channel.joined {
                            Text("已订阅")
                                .font(.system(size: 12))
                                .foregroundColor(c.textTertiary)
                        } else {
                            Button("订阅") {
                                Task {
                                    if let chat = await app.subscribeChannel(chatId: channel.id) {
                                        onOpen(chat)
                                        dismiss()
                                    }
                                }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(c.accent)
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(c.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(c.background.ignoresSafeArea())
            .navigationTitle("发现频道")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    private func search() async {
        loading = true
        channels = await app.discoverChannels(query: query.trimmingCharacters(in: .whitespaces))
        loading = false
    }
}
