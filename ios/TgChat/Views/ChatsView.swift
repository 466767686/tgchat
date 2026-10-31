import SwiftUI

struct ChatsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var path = NavigationPath()
    @State private var showNewChat = false
    @State private var showSettings = false
    @State private var showSearch = false
    @State private var showFolderManager = false
    @State private var selectedFolder: String? = nil
    @State private var wallpaperTarget: Chat?
    @State private var newFolderName = ""
    @State private var showCreateFolder = false
    @State private var showCall = false

    private var archivedChats: [Chat] { app.chats.filter { $0.archived } }
    private var activeChats: [Chat] {
        if selectedFolder == "__archive__" {
            return app.chats.filter { $0.archived }
        }
        var result = app.chats.filter { !$0.archived }
        if let folder = selectedFolder {
            if folder == "__unread__" {
                result = result.filter { $0.unread > 0 }
            } else {
                result = result.filter { $0.folderId == folder }
            }
        }
        return result
    }
    private var pinnedChats: [Chat] { activeChats.filter { $0.pinned } }
    private var otherChats: [Chat] { activeChats.filter { !$0.pinned } }

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header(c)
                folderBar(c)

                if app.chatsLoading && app.chats.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activeChats.isEmpty {
                    EmptyStateView(
                        title: "还没有会话",
                        subtitle: "点右上角的按钮开始聊天",
                        colors: c
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if !pinnedChats.isEmpty {
                                sectionHeader("置顶", colors: c)
                                ForEach(pinnedChats) { chat in
                                    chatRow(chat, colors: c)
                                }
                            }
                            if !otherChats.isEmpty {
                                if !pinnedChats.isEmpty {
                                    sectionHeader("其他", colors: c)
                                }
                                ForEach(otherChats) { chat in
                                    chatRow(chat, colors: c)
                                }
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
            SettingsView().environmentObject(app)
        }
        .sheet(isPresented: $showSearch) {
            GlobalSearchView { chat in
                showSearch = false
                path.append(chat)
            }
            .environmentObject(app)
        }
        .sheet(isPresented: $showFolderManager) {
            FolderManagerView().environmentObject(app)
        }
        .sheet(item: $wallpaperTarget) { chat in
            WallpaperPickerView(chat: chat).environmentObject(app)
        }
        .alert("新建文件夹", isPresented: $showCreateFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") {
                let name = newFolderName.trimmingCharacters(in: .whitespaces)
                newFolderName = ""
                guard !name.isEmpty else { return }
                Task {
                    if let folder = await app.createFolder(name) {
                        selectedFolder = folder.id
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .onReceive(CallService.shared.$state) { state in
            if state.isBusy { showCall = true }
        }
        .sheet(isPresented: $showCall, onDismiss: {
            if !CallService.shared.state.isBusy {
                CallService.shared.reset()
            }
        }) {
            CallView()
        }
        .task {
            await app.loadFolders()
        }
    }

    @ViewBuilder
    private func chatRow(_ chat: Chat, colors c: TgColors) -> some View {
        VStack(spacing: 0) {
        NavigationLink(value: chat) {
            ChatRowView(chat: chat, myId: app.me?.id, colors: c)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await app.batchChats("delete", chatIds: [chat.id]) }
            } label: {
                Label("删除", systemImage: "trash")
            }
            Button {
                Task { await app.batchChats(chat.archived ? "unarchive" : "archive", chatIds: [chat.id]) }
            } label: {
                Label(chat.archived ? "取消归档" : "归档", systemImage: "archivebox")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading) {
            Button {
                Task { await app.batchChats(chat.pinned ? "unpin" : "pin", chatIds: [chat.id]) }
            } label: {
                Label(chat.pinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                Task { await app.batchChats(chat.pinned ? "unpin" : "pin", chatIds: [chat.id]) }
            } label: {
                Label(chat.pinned ? "取消置顶" : "置顶", systemImage: "pin")
            }
            Button {
                Task { await app.batchChats(chat.archived ? "unarchive" : "archive", chatIds: [chat.id]) }
            } label: {
                Label(chat.archived ? "取消归档" : "归档", systemImage: "archivebox")
            }
            Button {
                Task { await app.batchChats("read", chatIds: [chat.id]) }
            } label: {
                Label("标为已读", systemImage: "checkmark.circle")
            }
            Button {
                wallpaperTarget = chat
            } label: {
                Label("聊天壁纸", systemImage: "photo")
            }
            Button(role: .destructive) {
                Task { await app.batchChats("delete", chatIds: [chat.id]) }
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }

        Divider().padding(.leading, 78)
        }
    }

    private func sectionHeader(_ title: String, colors c: TgColors) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(c.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func folderBar(_ c: TgColors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(title: "全部", active: selectedFolder == nil, colors: c) {
                    selectedFolder = nil
                }
                folderChip(title: "未读", active: selectedFolder == "__unread__", colors: c) {
                    selectedFolder = "__unread__"
                }
                if !archivedChats.isEmpty {
                    folderChip(title: "归档 \(archivedChats.count)", active: selectedFolder == "__archive__", colors: c) {
                        selectedFolder = "__archive__"
                    }
                }
                ForEach(app.folders) { folder in
                    folderChip(title: folder.name, active: selectedFolder == folder.id, colors: c) {
                        selectedFolder = folder.id
                    }
                }
                Button {
                    showFolderManager = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 14))
                        .foregroundColor(c.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func folderChip(title: String, active: Bool, colors c: TgColors, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? .white : c.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? c.accent : c.surfaceAlt))
        }
        .buttonStyle(.plain)
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
                Task {
                    if let chat = await app.openSavedChat() {
                        path.append(chat)
                    }
                }
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(c.textSecondary)
            }

            Button {
                showSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(c.textSecondary)
            }

            Button {
                showNewChat = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(c.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                    if chat.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textTertiary)
                    }
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

struct GlobalSearchView: View {
    let onOpen: (Chat) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var query = ""
    @State private var kind = ""
    @State private var results: [Message] = []
    @State private var searching = false

    private let kinds: [(String, String)] = [("", "全部"), ("text", "文字"), ("media", "媒体"), ("links", "链接")]

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(c.textTertiary)
                    TextField("搜索所有聊天", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await run() } }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(c.surfaceAlt))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                HStack(spacing: 8) {
                    ForEach(kinds, id: \.0) { item in
                        Button {
                            kind = item.0
                            Task { await run() }
                        } label: {
                            Text(item.1)
                                .font(.system(size: 12, weight: kind == item.0 ? .semibold : .regular))
                                .foregroundColor(kind == item.0 ? .white : c.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(kind == item.0 ? c.accent : c.surfaceAlt))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if searching {
                    ProgressView().padding()
                }

                List(results) { message in
                    Button {
                        if let chat = app.chat(byId: message.chatId) {
                            onOpen(chat)
                            dismiss()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(app.chat(byId: message.chatId)?.displayTitle(myId: app.me?.id) ?? "会话")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(c.accent)
                                Spacer()
                                Text(formatListTime(message.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(c.textTertiary)
                            }
                            Text(message.text.isEmpty ? "[媒体消息]" : message.text)
                                .font(.system(size: 14))
                                .foregroundColor(c.textPrimary)
                                .lineLimit(2)
                        }
                    }
                    .listRowBackground(c.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(c.background.ignoresSafeArea())
            .navigationTitle("全局搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func run() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { results = []; return }
        searching = true
        results = await app.globalSearch(text, kind: kind)
        searching = false
    }
}

struct FolderManagerView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var newName = ""

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section("新建文件夹") {
                    HStack {
                        TextField("名称", text: $newName)
                        Button("添加") {
                            let name = newName.trimmingCharacters(in: .whitespaces)
                            newName = ""
                            guard !name.isEmpty else { return }
                            Task { _ = await app.createFolder(name) }
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .listRowBackground(c.background)
                }

                Section("文件夹") {
                    if app.folders.isEmpty {
                        Text("还没有文件夹").foregroundColor(c.textTertiary).listRowBackground(c.background)
                    }
                    ForEach(app.folders) { folder in
                        HStack {
                            Text(folder.name).foregroundColor(c.textPrimary)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await app.deleteFolder(folder.id) }
                            } label: {
                                Image(systemName: "trash").foregroundColor(c.danger)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(c.background)
                    }
                }

                Section("把会话加入文件夹") {
                    ForEach(app.chats.filter { !$0.archived }) { chat in
                        Menu {
                            Button("移除") {
                                Task { await app.assignFolder(chatId: chat.id, folderId: nil) }
                            }
                            ForEach(app.folders) { folder in
                                Button(folder.name) {
                                    Task { await app.assignFolder(chatId: chat.id, folderId: folder.id) }
                                }
                            }
                        } label: {
                            HStack {
                                Text(chat.displayTitle(myId: app.me?.id))
                                    .foregroundColor(c.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(app.folders.first { $0.id == chat.folderId }?.name ?? "未分类")
                                    .font(.system(size: 12))
                                    .foregroundColor(c.textTertiary)
                            }
                        }
                        .listRowBackground(c.background)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("文件夹")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct WallpaperPickerView: View {
    let chat: Chat

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private let options: [(String, String)] = [
        ("默认", ""),
        ("蓝色", "blue"),
        ("绿色", "green"),
        ("紫色", "purple"),
        ("橙色", "orange"),
        ("粉色", "pink"),
        ("深色", "dark"),
        ("灰色", "gray"),
    ]

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(options, id: \.1) { option in
                        Button {
                            Task {
                                await app.setWallpaper(chatId: chat.id, wallpaper: option.1.isEmpty ? nil : option.1)
                            }
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(wallpaperColors(option.1).0)
                                    .frame(height: 90)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                chat.wallpaper == (option.1.isEmpty ? nil : option.1)
                                                    ? c.accent : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                Text(option.0)
                                    .font(.system(size: 12))
                                    .foregroundColor(c.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(c.background.ignoresSafeArea())
            .navigationTitle("聊天壁纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

func wallpaperColors(_ name: String?) -> (LinearGradient, Color) {
    let top: Color
    let bottom: Color
    switch name {
    case "blue":
        top = Color(hex: "#BFD9FF"); bottom = Color(hex: "#E8F1FF")
    case "green":
        top = Color(hex: "#C8E8D0"); bottom = Color(hex: "#EAF6EC")
    case "purple":
        top = Color(hex: "#D9CDF5"); bottom = Color(hex: "#F1ECFB")
    case "orange":
        top = Color(hex: "#FFD9B8"); bottom = Color(hex: "#FFF0E4")
    case "pink":
        top = Color(hex: "#FFD1E0"); bottom = Color(hex: "#FFF0F5")
    case "dark":
        top = Color(hex: "#1F2430"); bottom = Color(hex: "#12151C")
    case "gray":
        top = Color(hex: "#E3E5E8"); bottom = Color(hex: "#F4F5F7")
    default:
        top = Color(hex: "#DCE6F2"); bottom = Color(hex: "#EEF3F9")
    }
    return (LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom), bottom)
}
