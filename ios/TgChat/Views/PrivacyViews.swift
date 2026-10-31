import SwiftUI

struct ProfileEditView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var displayName = ""
    @State private var bio = ""
    @State private var color = "#3390EC"
    @State private var saving = false

    private let colors = ["#3390EC", "#7BC862", "#FAA774", "#A695E7", "#E0645A", "#5AB0E0", "#E0A040", "#8E8E93"]

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(name: displayName.isEmpty ? "?" : displayName, colorHex: color, size: 84)
                        Spacer()
                    }
                    .listRowBackground(c.background)
                }

                Section("昵称") {
                    TextField("昵称", text: $displayName)
                        .listRowBackground(c.background)
                }

                Section("简介") {
                    TextField("介绍一下自己…", text: $bio, axis: .vertical)
                        .lineLimit(1...4)
                        .listRowBackground(c.background)
                }

                Section("头像颜色") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(colors, id: \.self) { hex in
                            Button {
                                color = hex
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: color == hex ? 3 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(c.background)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            _ = await app.updateProfile([
                                "displayName": displayName.trimmingCharacters(in: .whitespaces),
                                "bio": bio,
                                "avatarColor": color,
                            ])
                            dismiss()
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
            .onAppear {
                displayName = app.me?.displayName ?? ""
                bio = app.me?.bio ?? ""
                color = app.me?.avatarColor ?? "#3390EC"
            }
        }
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var visibility = "everyone"
    @State private var readReceipts = true

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        List {
            Section {
                Picker("在线状态可见性", selection: $visibility) {
                    Text("所有人").tag("everyone")
                    Text("我的联系人").tag("contacts")
                    Text("没有人").tag("nobody")
                }
                .onChange(of: visibility) { value in
                    Task { _ = await app.updateProfile(["lastSeenVisibility": value]) }
                }
                .listRowBackground(c.background)
            } footer: {
                Text("控制谁能看到你的“最近在线”。")
                    .font(.system(size: 12))
            }

            Section {
                Toggle("已读回执", isOn: $readReceipts)
                    .onChange(of: readReceipts) { value in
                        Task { _ = await app.updateProfile(["readReceipts": value]) }
                    }
                    .listRowBackground(c.background)
            } footer: {
                Text("关闭后对方看不到你的已读状态。")
                    .font(.system(size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(c.background.ignoresSafeArea())
        .navigationTitle("隐私与安全")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            visibility = app.me?.lastSeenVisibility ?? "everyone"
            readReceipts = app.me?.readReceipts ?? true
        }
    }
}

struct BlocklistView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var users: [User] = []
    @State private var loading = true

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        List {
            if loading {
                ProgressView().listRowBackground(c.background)
            } else if users.isEmpty {
                Text("黑名单为空")
                    .foregroundColor(c.textTertiary)
                    .listRowBackground(c.background)
            }
            ForEach(users) { user in
                HStack(spacing: 12) {
                    AvatarView(name: user.title, colorHex: user.avatarColor, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.title).foregroundColor(c.textPrimary)
                        Text("@\(user.username)")
                            .font(.system(size: 12))
                            .foregroundColor(c.textSecondary)
                    }
                    Spacer()
                    Button("解除") {
                        Task {
                            await app.unblockUser(user.id)
                            users.removeAll { $0.id == user.id }
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(c.accent)
                    .buttonStyle(.plain)
                }
                .listRowBackground(c.background)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(c.background.ignoresSafeArea())
        .navigationTitle("黑名单")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            users = await app.loadBlocks()
            loading = false
        }
    }
}

struct SessionsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var sessions: [SessionInfo] = []
    @State private var loading = true

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        List {
            if loading {
                ProgressView().listRowBackground(c.background)
            }
            ForEach(sessions) { session in
                HStack(spacing: 12) {
                    Image(systemName: session.platform.lowercased().contains("ios") ? "iphone" : "laptopcomputer")
                        .font(.system(size: 22))
                        .foregroundColor(c.accent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(session.device).foregroundColor(c.textPrimary)
                            if session.current {
                                Text("当前设备")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(c.accent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(c.accent.opacity(0.15)))
                            }
                        }
                        Text("最近活动：\(formatListTime(session.lastActiveAt))")
                            .font(.system(size: 12))
                            .foregroundColor(c.textSecondary)
                    }
                    Spacer()
                    if !session.current {
                        Button("下线") {
                            Task {
                                await app.revokeSession(session.id)
                                sessions = await app.loadSessions()
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(c.danger)
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(c.background)
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await app.revokeOtherSessions()
                        sessions = await app.loadSessions()
                    }
                } label: {
                    Text("退出其他所有会话")
                }
                .listRowBackground(c.background)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(c.background.ignoresSafeArea())
        .navigationTitle("会话管理")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            sessions = await app.loadSessions()
            loading = false
        }
    }
}

struct NotificationSettingsView: View {
    @Environment(\.colorScheme) private var scheme

    @AppStorage("notify.messages") private var notifyMessages = true
    @AppStorage("notify.groups") private var notifyGroups = true
    @AppStorage("notify.calls") private var notifyCalls = true
    @AppStorage("notify.sound") private var notifySound = true

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        List {
            Section {
                Toggle("私聊消息", isOn: $notifyMessages).listRowBackground(c.background)
                Toggle("群组消息", isOn: $notifyGroups).listRowBackground(c.background)
                Toggle("通话来电", isOn: $notifyCalls).listRowBackground(c.background)
                Toggle("提示音", isOn: $notifySound).listRowBackground(c.background)
            } footer: {
                Text("通知由系统本地通知发送；强制退出应用后将无法接收。")
                    .font(.system(size: 12))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(c.background.ignoresSafeArea())
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct E2EEInfoView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("端到端加密架构")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(c.textPrimary)

                Text("当前版本：传输层使用 HTTPS/WSS 加密，消息在服务端以明文存储（D1），尚未启用端到端加密。下面是计划采用的架构。")
                    .font(.system(size: 14))
                    .foregroundColor(c.textSecondary)

                group(c, title: "1. 身份密钥", lines: [
                    "每个设备生成长期身份密钥对（Curve25519）。",
                    "公钥上传服务端，私钥仅保存在设备 Keychain，永不上传。",
                ])

                group(c, title: "2. 会话建立", lines: [
                    "私聊首次发消息使用 X3DH 建立共享密钥。",
                    "双方各发送一次性预共享公钥（PreKey），服务端只做公钥目录。",
                    "群聊使用 Sender Keys：成员各自生成链式密钥，通过私聊分发。",
                ])

                group(c, title: "3. 消息加密", lines: [
                    "每条消息用 AES-256-GCM 加密，密钥来自 Double Ratchet 链。",
                    "服务端只存储密文 + 序号 + 时间，无法解密。",
                    "媒体先本地加密再上传 R2，密钥随消息一起加密传输。",
                ])

                group(c, title: "4. 服务端职责", lines: [
                    "D1 仅保存密文与公开密钥，R2 保存加密后的媒体块。",
                    "Durable Objects 只转发密文与信令，不接触明文。",
                    "多设备通过设备公钥列表分发会话密钥，新设备不会解密历史消息（除非主动同步）。",
                ])

                group(c, title: "5. 验证与安全码", lines: [
                    "双方可对比 60 位安全码，确认没有中间人。",
                    "会话密钥定期轮换（Double Ratchet），泄露后可恢复。",
                ])

                Text("实现状态：协议与数据结构设计完成，客户端加密层尚未接入。接入后旧聊天记录仍为明文，需要重新建立会话。")
                    .font(.system(size: 13))
                    .foregroundColor(c.textTertiary)
                    .padding(.top, 6)
            }
            .padding(20)
        }
        .background(c.background.ignoresSafeArea())
        .navigationTitle("端到端加密")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ c: TgColors, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(c.textPrimary)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("•").foregroundColor(c.accent)
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundColor(c.textSecondary)
                }
            }
        }
        .padding(.top, 4)
    }
}
