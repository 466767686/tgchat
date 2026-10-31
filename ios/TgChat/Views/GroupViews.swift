import UIKit
import SwiftUI

struct GroupCreateView: View {
    let onCreated: (Chat) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var title = ""
    @State private var selected: Set<String> = []
    @State private var creating = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section {
                    TextField("群名称（例如：家庭群）", text: $title)
                        .font(.system(size: 16))
                        .listRowBackground(c.background)
                }

                Section("选择成员（\(selected.count)）") {
                    ForEach(app.usersDirectory) { user in
                        Button {
                            if selected.contains(user.id) {
                                selected.remove(user.id)
                            } else {
                                selected.insert(user.id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(name: user.title, colorHex: user.avatarColor, size: 42)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(c.textPrimary)
                                    Text("@\(user.username)")
                                        .font(.system(size: 12))
                                        .foregroundColor(c.textSecondary)
                                }
                                Spacer()
                                Image(systemName: selected.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(user.id) ? c.accent : c.textTertiary)
                            }
                        }
                        .listRowBackground(c.background)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("新建群组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        create()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty || creating)
                }
            }
        }
    }

    private func create() {
        creating = true
        let name = title.trimmingCharacters(in: .whitespaces)
        Task {
            if let chat = await app.createGroup(title: name, memberIds: Array(selected)) {
                onCreated(chat)
                dismiss()
            }
            creating = false
        }
    }
}

struct GroupInfoView: View {
    let chatId: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var editField: EditField?
    @State private var editValue = ""
    @State private var inviteLink: String?
    @State private var showAddMember = false
    @State private var confirmLeave = false
    @State private var confirmDissolve = false
    @State private var showReports = false
    @State private var reports: [ReportItem] = []

    private var chat: Chat? { app.chat(byId: chatId) }
    private var myId: String? { app.me?.id }
    private var me: User? { chat?.members.first { $0.id == myId } }

    enum EditField: String, Identifiable {
        case title, description, announcement
        var id: String { rawValue }
        var label: String {
            switch self {
            case .title: return "群名称"
            case .description: return "群简介"
            case .announcement: return "群公告"
            }
        }
    }

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                if let chat = chat {
                    Section {
                        HStack(spacing: 14) {
                            AvatarView(
                                name: chat.displayTitle(myId: myId),
                                colorHex: chat.avatarColor(myId: myId),
                                size: 58
                            )
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.displayTitle(myId: myId))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(c.textPrimary)
                                Text("\(chat.members.count) 位成员")
                                    .font(.system(size: 13))
                                    .foregroundColor(c.textSecondary)
                                if let description = chat.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 13))
                                        .foregroundColor(c.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                        }
                        .listRowBackground(c.background)
                    }

                    Section("群组信息") {
                        if chat.canManage {
                            row("编辑群名称", value: chat.displayTitle(myId: myId), colors: c) {
                                editValue = chat.title ?? ""
                                editField = .title
                            }
                            row("编辑群简介", value: chat.description ?? "未设置", colors: c) {
                                editValue = chat.description ?? ""
                                editField = .description
                            }
                            row("群公告", value: chat.announcement ?? "未设置", colors: c) {
                                editValue = chat.announcement ?? ""
                                editField = .announcement
                            }
                        } else if let announcement = chat.announcement, !announcement.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("群公告").font(.system(size: 13)).foregroundColor(c.textSecondary)
                                Text(announcement).font(.system(size: 14)).foregroundColor(c.textPrimary)
                            }
                            .listRowBackground(c.background)
                        }

                        if chat.canManage {
                            Button {
                                Task {
                                    if let link = await app.createGroupInvite(chatId: chatId) {
                                        inviteLink = link
                                        UIPasteboard.general.string = link
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("创建邀请链接").foregroundColor(c.accent)
                                    Spacer()
                                    Text(inviteLink ?? "复制到剪贴板")
                                        .font(.system(size: 12))
                                        .foregroundColor(c.textTertiary)
                                        .lineLimit(1)
                                }
                            }
                            .listRowBackground(c.background)
                        }
                    }

                    if chat.canManage {
                        Section("群组设置") {
                            Menu {
                                ForEach([0, 5, 10, 30, 60, 300], id: \.self) { value in
                                    Button(value == 0 ? "关闭" : "\(value) 秒") {
                                        Task { await app.updateChat(chatId: chatId, fields: ["slowMode": value]) }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("慢速模式").foregroundColor(c.textPrimary)
                                    Spacer()
                                    Text(slowText(chat))
                                        .font(.system(size: 13))
                                        .foregroundColor(c.textTertiary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(c.textTertiary)
                                }
                            }
                            .listRowBackground(c.background)

                            Menu {
                                ForEach([0, 3600, 86400, 604800], id: \.self) { value in
                                    Button(autoDeleteLabel(value)) {
                                        Task { await app.updateChat(chatId: chatId, fields: ["autoDeleteSeconds": value]) }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("定时删除").foregroundColor(c.textPrimary)
                                    Spacer()
                                    Text(autoDeleteLabel(chat.autoDeleteSeconds ?? 0))
                                        .font(.system(size: 13))
                                        .foregroundColor(c.textTertiary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(c.textTertiary)
                                }
                            }
                            .listRowBackground(c.background)

                            Toggle("隐藏历史消息", isOn: Binding(
                                get: { chat.historyVisible == false },
                                set: { value in
                                    Task { await app.updateChat(chatId: chatId, fields: ["historyVisible": !value]) }
                                }
                            ))
                            .listRowBackground(c.background)

                            Toggle("话题模式", isOn: Binding(
                                get: { chat.topicsEnabled == true },
                                set: { value in
                                    Task { await app.updateChat(chatId: chatId, fields: ["topicsEnabled": value]) }
                                }
                            ))
                            .listRowBackground(c.background)

                            Button {
                                showReports = true
                                Task { reports = await app.loadReports(chatId: chatId) }
                            } label: {
                                HStack {
                                    Text("举报处理").foregroundColor(c.textPrimary)
                                    Spacer()
                                    Text("\(reports.filter { $0.status == "open" }.count) 条待处理")
                                        .font(.system(size: 12))
                                        .foregroundColor(c.textTertiary)
                                }
                            }
                            .listRowBackground(c.background)
                        }
                    }

                    Section("成员（\(chat.members.count)）") {
                        ForEach(chat.members) { member in
                            memberRow(member, chat: chat, colors: c)
                        }
                        if chat.canManage {
                            Button {
                                showAddMember = true
                            } label: {
                                Label("添加成员", systemImage: "person.badge.plus")
                                    .foregroundColor(c.accent)
                            }
                            .listRowBackground(c.background)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            confirmLeave = true
                        } label: {
                            Text("退出群组")
                        }
                        .listRowBackground(c.background)

                        if chat.isOwner {
                            Button(role: .destructive) {
                                confirmDissolve = true
                            } label: {
                                Text("解散群组")
                            }
                            .listRowBackground(c.background)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("群组信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .alert(
                editField?.label ?? "",
                isPresented: Binding(
                    get: { editField != nil },
                    set: { if !$0 { editField = nil } }
                )
            ) {
                TextField("输入内容", text: $editValue)
                Button("保存") {
                    guard let field = editField else { return }
                    let value = editValue
                    editField = nil
                    Task { await app.updateChat(chatId: chatId, fields: [field.rawValue: value]) }
                }
                Button("取消", role: .cancel) {}
            }
            .sheet(isPresented: $showReports) {
                ReportsView(chatId: chatId)
                    .environmentObject(app)
            }
            .sheet(isPresented: $showAddMember) {
                AddMemberView(chatId: chatId)
                    .environmentObject(app)
            }
            .confirmationDialog("确定退出群组？", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("退出", role: .destructive) {
                    Task {
                        await app.leaveGroup(chatId: chatId)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("解散后所有消息将被删除", isPresented: $confirmDissolve, titleVisibility: .visible) {
                Button("解散群组", role: .destructive) {
                    Task {
                        await app.dissolveGroup(chatId: chatId)
                        dismiss()
                    }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    private func autoDeleteLabel(_ seconds: Int) -> String {
        switch seconds {
        case 0: return "关闭"
        case 3600: return "1 小时"
        case 86400: return "1 天"
        case 604800: return "7 天"
        default: return "\(seconds) 秒"
        }
    }

    private func slowText(_ chat: Chat) -> String {
        switch chat.slowMode ?? 0 {
        case 0: return "关闭"
        case let value: return "\(value) 秒"
        }
    }

    private func row(_ label: String, value: String, colors c: TgColors, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundColor(c.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(c.textTertiary)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(c.textTertiary)
            }
        }
        .listRowBackground(c.background)
    }

    private func memberRow(_ member: User, chat: Chat, colors c: TgColors) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: member.title, colorHex: member.avatarColor, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.title)
                        .font(.system(size: 15))
                        .foregroundColor(c.textPrimary)
                    if member.isOwnerRole {
                        Text("群主")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(c.accent))
                    } else if member.isAdminRole {
                        Text("管理员")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(c.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(c.accent.opacity(0.15)))
                    }
                    if member.isMuted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: 10))
                            .foregroundColor(c.danger)
                    }
                }
                Text("@\(member.username)")
                    .font(.system(size: 12))
                    .foregroundColor(c.textSecondary)
            }
            Spacer()
        }
        .listRowBackground(c.background)
        .contextMenu {
            if chat.isOwner && member.id != myId && !member.isOwnerRole {
                Button {
                    Task {
                        await app.setGroupRole(
                            chatId: chatId,
                            userId: member.id,
                            role: member.isAdminRole ? "member" : "admin"
                        )
                    }
                } label: {
                    Label(member.isAdminRole ? "取消管理员" : "设为管理员", systemImage: "star")
                }
            }
            if chat.canManage && member.id != myId && !member.isOwnerRole {
                Button {
                    Task { await app.muteGroupMember(chatId: chatId, userId: member.id, muted: !member.isMuted) }
                } label: {
                    Label(member.isMuted ? "解除禁言" : "禁言", systemImage: "speaker.slash")
                }
                Button(role: .destructive) {
                    Task { await app.removeGroupMember(chatId: chatId, userId: member.id) }
                } label: {
                    Label("移出群组", systemImage: "person.badge.minus")
                }
            }
        }
    }
}

struct AddMemberView: View {
    let chatId: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TgColors(dark: scheme == .dark)
        let existing = Set(app.chat(byId: chatId)?.members.map { $0.id } ?? [])

        NavigationStack {
            List {
                ForEach(app.usersDirectory.filter { !existing.contains($0.id) }) { user in
                    Button {
                        Task {
                            await app.addGroupMember(chatId: chatId, userId: user.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: user.title, colorHex: user.avatarColor, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.title)
                                    .font(.system(size: 15))
                                    .foregroundColor(c.textPrimary)
                                Text("@\(user.username)")
                                    .font(.system(size: 12))
                                    .foregroundColor(c.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus.circle").foregroundColor(c.accent)
                        }
                    }
                    .listRowBackground(c.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("添加成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}


struct MentionPickerView: View {
    let users: [User]
    let onSelect: (User) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List(users) { user in
                Button {
                    onSelect(user)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(name: user.title, colorHex: user.avatarColor, size: 36)
                        Text(user.title).foregroundColor(c.textPrimary)
                        Spacer()
                        Text("@\(user.username)")
                            .font(.system(size: 12))
                            .foregroundColor(c.textTertiary)
                    }
                }
                .listRowBackground(c.background)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("提及成员")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct ReportsView: View {
    let chatId: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var reports: [ReportItem] = []

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                if reports.isEmpty {
                    Text("暂无举报").foregroundColor(c.textTertiary).listRowBackground(c.background)
                }
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("举报人：\(report.reporter)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(c.accent)
                            Spacer()
                            Text(report.status == "open" ? "待处理" : "已处理")
                                .font(.system(size: 11))
                                .foregroundColor(report.status == "open" ? c.danger : c.textTertiary)
                        }
                        Text("原因：\(report.reason)")
                            .font(.system(size: 13))
                            .foregroundColor(c.textPrimary)
                        Text("消息：\(report.text.isEmpty ? "(非文本消息)" : report.text)")
                            .font(.system(size: 13))
                            .foregroundColor(c.textSecondary)
                            .lineLimit(3)
                        if report.status == "open" {
                            Button("标记已处理") {
                                Task {
                                    try? await APIClient.shared.resolveReport(chatId: chatId, reportId: report.id)
                                    reports = await app.loadReports(chatId: chatId)
                                }
                            }
                            .font(.system(size: 12))
                        }
                    }
                    .listRowBackground(c.background)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("举报")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                reports = await app.loadReports(chatId: chatId)
            }
        }
    }
}
