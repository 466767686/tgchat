import SDWebImage
import SDWebImageWebPCoder
import SwiftUI
import UIKit

// MARK: - Imported Telegram sticker packs

struct ImportedStickerPack: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var files: [String]
}

@MainActor
final class StickerLibrary: ObservableObject {
    static let shared = StickerLibrary()

    @Published var packs: [ImportedStickerPack] = []

    private let fm = FileManager.default
    private var root: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("TelegramStickers", isDirectory: true)
    }

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    init() {
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ImportedStickerPack].self, from: data) else {
            packs = []
            return
        }
        packs = decoded
    }

    private func persist() {
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(packs) {
            try? data.write(to: indexURL)
        }
    }

    func fileURL(pack: ImportedStickerPack, index: Int) -> URL {
        root.appendingPathComponent(pack.id).appendingPathComponent(pack.files[index])
    }

    func delete(_ pack: ImportedStickerPack) {
        try? fm.removeItem(at: root.appendingPathComponent(pack.id))
        packs.removeAll { $0.id == pack.id }
        persist()
    }

    func importPack(
        link: String,
        token: String,
        progress: @escaping (Double) -> Void
    ) async throws -> (pack: ImportedStickerPack, skipped: Int) {
        let resolved = try await APIClient.shared.resolveStickerSet(token: token, name: link)
        let staticStickers = resolved.stickers.filter { !$0.animated && !$0.video }
        guard !staticStickers.isEmpty else {
            throw StickerImportError.noStaticStickers
        }

        let limited = Array(staticStickers.prefix(60))
        let packId = "\(resolved.name)-\(UUID().uuidString.prefix(6))"
        let dir = root.appendingPathComponent(packId)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        var files: [String] = []
        for (index, sticker) in limited.enumerated() {
            let data = try await APIClient.shared.stickerFile(token: token, fileId: sticker.fileId)
            guard let image = SDImageWebPCoder.shared.decodedImage(with: data, options: nil),
                  let png = image.pngData() else {
                continue
            }
            let name = String(format: "%03d.png", index)
            try png.write(to: dir.appendingPathComponent(name))
            files.append(name)
            progress(Double(index + 1) / Double(limited.count))
        }

        guard !files.isEmpty else {
            throw StickerImportError.decodeFailed
        }

        let pack = ImportedStickerPack(id: packId, title: resolved.title, files: files)
        packs.append(pack)
        persist()
        return (pack, resolved.stickers.count - staticStickers.count)
    }
}

enum StickerImportError: LocalizedError {
    case noStaticStickers
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .noStaticStickers: return "这个贴纸包只有动态贴纸（.tgs/.webm），当前版本只支持静态贴纸"
        case .decodeFailed: return "贴纸解码失败"
        }
    }
}

// MARK: - Emoji catalog

struct EmojiCategory: Identifiable {
    let id: String
    let title: String
    let emojis: [String]
}

enum EmojiCatalog {
    static let categories: [EmojiCategory] = [
        EmojiCategory(id: "faces", title: "表情", emojis: [
            "😀", "😂", "🥰", "😎", "🤔", "😭", "😡", "🤯",
            "😃", "😄", "😁", "😆", "😅", "🤣", "😊", "😇",
            "🙂", "🙃", "😉", "😌", "😍", "😘", "😗", "😙",
            "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓",
            "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️",
            "😣", "😖", "😫", "😩", "🥺", "😢", "😤", "😠",
            "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓",
            "🤗", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬",
            "🙄", "😯", "😦", "😧", "😮", "😲", "🥱", "😴",
        ]),
        EmojiCategory(id: "hands", title: "手势", emojis: [
            "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "✌️",
            "🤞", "👌", "🤙", "👋", "🫶", "🤟", "☝️", "✊",
            "👊", "🤛", "🤜", "👐", "🤲", "🫡", "🫰", "🤌",
        ]),
        EmojiCategory(id: "nature", title: "自然", emojis: [
            "🌙", "☀️", "⭐️", "🌈", "🍀", "🌸", "🌻", "🌹",
            "🌊", "🔥", "❄️", "⚡️", "🌵", "🌴", "🐱", "🐶",
            "🐼", "🦊", "🐰", "🐻", "🦁", "🐯", "🐨", "🐷",
        ]),
        EmojiCategory(id: "things", title: "物品", emojis: [
            "🎉", "🎊", "🎁", "🎈", "🏆", "💯", "✅", "❌",
            "☕️", "🍺", "🍕", "🍰", "🚀", "💡", "📌", "🔔",
            "💎", "💰", "📱", "💻", "🎧", "🎮", "⚽️", "🏀",
        ]),
    ]
}

// MARK: - Panel

struct StickerPanel: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    let chatId: String
    @Binding var tab: Int
    var onEmoji: (String) -> Void
    var onClose: () -> Void = {}

    @StateObject private var library = StickerLibrary.shared
    @State private var category = 0
    @State private var selectedPack: String?
    @State private var showImport = false
    @State private var packToDelete: ImportedStickerPack?

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                tabButton(title: "表情", index: 0, colors: c)
                tabButton(title: "贴纸", index: 1, colors: c)
                Spacer()
                if tab == 1 {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(c.accent)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(c.accent.opacity(0.12)))
                    }
                }
                Button(action: onClose) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(c.textSecondary)
                        .frame(width: 30, height: 30)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if tab == 0 {
                emojiPanel(c)
            } else {
                stickerPanel(c)
            }
        }
        .frame(height: 300)
        .background(c.surfaceAlt)
        .sheet(isPresented: $showImport) {
            StickerImportView { pack in
                selectedPack = pack.id
            }
            .environmentObject(app)
        }
        .confirmationDialog(
            "删除贴纸包「\(packToDelete?.title ?? "")」？",
            isPresented: Binding(get: { packToDelete != nil }, set: { if !$0 { packToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let pack = packToDelete {
                    library.delete(pack)
                    if selectedPack == pack.id { selectedPack = nil }
                }
                packToDelete = nil
            }
            Button("取消", role: .cancel) { packToDelete = nil }
        }
    }

    private func tabButton(title: String, index: Int, colors c: TgColors) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                tab = index
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: tab == index ? .semibold : .regular))
                .foregroundColor(tab == index ? .white : c.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(tab == index ? c.accent : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func emojiPanel(_ c: TgColors) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(EmojiCatalog.categories.enumerated()), id: \.element.id) { index, item in
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { category = index }
                        } label: {
                            Text(item.title)
                                .font(.system(size: 11, weight: category == index ? .semibold : .regular))
                                .foregroundColor(category == index ? c.accent : c.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(category == index ? c.accent.opacity(0.12) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                    spacing: 4
                ) {
                    ForEach(EmojiCatalog.categories[category].emojis, id: \.self) { emoji in
                        Button {
                            onEmoji(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func stickerPanel(_ c: TgColors) -> some View {
        if library.packs.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 30))
                    .foregroundColor(c.textTertiary)
                Text("还没有贴纸包")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(c.textSecondary)
                Text("从 Telegram 链接添加，例如\nhttps://t.me/addstickers/HotCherry")
                    .font(.system(size: 12))
                    .foregroundColor(c.textTertiary)
                    .multilineTextAlignment(.center)
                Button("添加贴纸") { showImport = true }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(c.accent))
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        } else {
            let pack = library.packs.first(where: { $0.id == selectedPack }) ?? library.packs[0]
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 8
                    ) {
                        ForEach(Array(pack.files.enumerated()), id: \.offset) { index, _ in
                            Button {
                                sendSticker(pack: pack, index: index)
                            } label: {
                                LocalStickerImage(
                                    url: library.fileURL(pack: pack, index: index),
                                    size: 72
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(library.packs) { item in
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { selectedPack = item.id }
                            } label: {
                                LocalStickerImage(
                                    url: item.files.isEmpty ? nil : library.fileURL(pack: item, index: 0),
                                    size: 30
                                )
                                .padding(3)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(item.id == pack.id ? c.accent.opacity(0.18) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .onLongPressGesture { packToDelete = item }
                        }
                        Button { showImport = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(c.accent)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(c.accent.opacity(0.12)))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .background(c.background)
            }
            .transition(.opacity)
        }
    }

    private func sendSticker(pack: ImportedStickerPack, index: Int) {
        let url = library.fileURL(pack: pack, index: index)
        app.sendMedia(
            chatId: chatId,
            fileURL: url,
            kind: "sticker",
            mime: "image/png",
            name: "sticker.png",
            caption: "",
            width: 512,
            height: 512
        )
    }
}

struct LocalStickerImage: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Import sheet

struct StickerImportView: View {
    let onImported: (ImportedStickerPack) -> Void

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var link = ""
    @State private var token = UserDefaults.standard.string(forKey: "tg.botToken") ?? ""
    @State private var importing = false
    @State private var progress: Double = 0
    @State private var error: String?
    @State private var note: String?

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            List {
                Section {
                    TextField("https://t.me/addstickers/...", text: $link)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(c.background)
                } header: {
                    Text("贴纸包链接")
                } footer: {
                    Text("在 Telegram 中打开贴纸包 → 分享链接，粘贴到这里。")
                        .font(.system(size: 12))
                }

                Section {
                    SecureField("机器人 Token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(c.background)
                } header: {
                    Text("Telegram 机器人 Token")
                } footer: {
                    Text("在 @BotFather 发送 /newbot 创建机器人，把得到的 Token 填在这里（只保存在本机）。")
                        .font(.system(size: 12))
                }

                if importing {
                    Section {
                        ProgressView(value: progress).tint(c.accent).listRowBackground(c.background)
                        Text("正在导入 \(Int(progress * 100))%")
                            .font(.system(size: 12))
                            .foregroundColor(c.textSecondary)
                            .listRowBackground(c.background)
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .font(.system(size: 13))
                            .foregroundColor(c.danger)
                            .listRowBackground(c.background)
                    }
                }

                if let note = note {
                    Section {
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundColor(c.textSecondary)
                            .listRowBackground(c.background)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(c.background.ignoresSafeArea())
            .navigationTitle("添加 Telegram 贴纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { start() }
                        .disabled(importing || link.trimmingCharacters(in: .whitespaces).isEmpty || token.isEmpty)
                }
            }
        }
    }

    private func start() {
        error = nil
        note = nil
        importing = true
        progress = 0
        UserDefaults.standard.set(token, forKey: "tg.botToken")

        Task {
            do {
                let result = try await StickerLibrary.shared.importPack(
                    link: link.trimmingCharacters(in: .whitespaces),
                    token: token
                ) { value in
                    Task { @MainActor in progress = value }
                }
                onImported(result.pack)
                if result.skipped > 0 {
                    note = "已导入 \(result.pack.files.count) 个静态贴纸，跳过 \(result.skipped) 个动态贴纸"
                }
                try? await Task.sleep(nanoseconds: 600_000_000)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            importing = false
        }
    }
}

// MARK: - Animated GIF rendering (legacy gif messages)

struct AnimatedImageView: UIViewRepresentable {
    let url: URL?
    let token: String?
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        guard context.coordinator.current != url?.absoluteString else { return }
        context.coordinator.current = url?.absoluteString
        view.image = nil
        guard let url = url else { return }

        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                view.image = image
                view.startAnimating()
            }
            return
        }

        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                view.image = image
                view.startAnimating()
            }
        }.resume()
    }

    final class Coordinator {
        var current: String?
    }
}
