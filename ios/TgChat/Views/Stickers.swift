import SwiftUI
import UIKit

// MARK: - Sticker packs

struct StickerPack: Identifiable {
    let id: String
    let title: String
    let emojis: [String]
}

struct GifItem: Identifiable {
    let id: String
    let title: String
    let file: String
    let tags: [String]
}

enum StickerStore {
    static let packs: [StickerPack] = [
        StickerPack(id: "faces", title: "表情", emojis: [
            "😀", "😂", "🥰", "😎", "🤔", "😭", "😡", "🤯",
            "😴", "🤢", "🥳", "😇", "🤠", "🤡", "👻", "💀",
        ]),
        StickerPack(id: "hands", title: "手势", emojis: [
            "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "✌️",
            "🤞", "👌", "🤙", "👋", "🫶", "🤟", "☝️", "✊",
        ]),
        StickerPack(id: "love", title: "爱心", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍",
            "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘",
        ]),
        StickerPack(id: "party", title: "庆祝", emojis: [
            "🎉", "🎊", "🔥", "⭐️", "✨", "💯", "✅", "❌",
            "⚡️", "🌙", "☀️", "🌈", "🍀", "🎁", "🎈", "🏆",
        ]),
    ]

    static let gifs: [GifItem] = [
        GifItem(id: "heart_pulse", title: "心跳", file: "heart_pulse", tags: ["爱心", "喜欢", "heart"]),
        GifItem(id: "ball_bounce", title: "弹跳", file: "ball_bounce", tags: ["球", "开心", "ball"]),
        GifItem(id: "face_blink", title: "眨眼", file: "face_blink", tags: ["表情", "笑", "smile"]),
        GifItem(id: "star_twinkle", title: "闪星", file: "star_twinkle", tags: ["星星", "赞", "star"]),
        GifItem(id: "dots_waiting", title: "等待", file: "dots_waiting", tags: ["等待", "加载", "wait"]),
        GifItem(id: "confetti_party", title: "庆祝", file: "confetti_party", tags: ["庆祝", "派对", "party"]),
    ]

    private static let recentKey = "sticker.recent"
    private static let recentGifKey = "gif.recent"
    private static let maxRecent = 16

    static func recent() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    static func addRecent(_ emoji: String) {
        var items = recent()
        items.removeAll { $0 == emoji }
        items.insert(emoji, at: 0)
        if items.count > maxRecent { items = Array(items.prefix(maxRecent)) }
        UserDefaults.standard.set(items, forKey: recentKey)
    }

    static func recentGifs() -> [String] {
        UserDefaults.standard.stringArray(forKey: recentGifKey) ?? []
    }

    static func addRecentGif(_ id: String) {
        var items = recentGifs()
        items.removeAll { $0 == id }
        items.insert(id, at: 0)
        if items.count > maxRecent { items = Array(items.prefix(maxRecent)) }
        UserDefaults.standard.set(items, forKey: recentGifKey)
    }

    /// Renders an emoji into a square PNG so it can be uploaded as a sticker.
    static func stickerPNG(_ emoji: String, side: CGFloat = 240) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let image = renderer.image { _ in
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.82),
            ]
            let text = emoji as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2),
                withAttributes: attributes
            )
        }
        return image.pngData()
    }

    static func gifURL(_ file: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: "gif")
            ?? Bundle.main.url(forResource: file, withExtension: "gif", subdirectory: "gifs")
    }

    static func gifData(_ id: String) -> Data? {
        guard let item = gifs.first(where: { $0.id == id }),
              let url = gifURL(item.file) else { return nil }
        return try? Data(contentsOf: url)
    }
}

// MARK: - Animated GIF view

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
            if let data = try? Data(contentsOf: url) {
                view.image = UIImage(data: data)
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

// MARK: - Sticker / GIF panel

struct StickerPanel: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    let chatId: String

    @State private var mode = 0
    @State private var selectedPack = "faces"
    @State private var recents: [String] = StickerStore.recent()
    @State private var recentGifIds: [String] = StickerStore.recentGifs()
    @State private var gifQuery = ""

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("贴纸").tag(0)
                Text("GIF").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 40)
            .padding(.vertical, 6)

            if mode == 0 {
                stickerContent(c)
            } else {
                gifContent(c)
            }
        }
        .background(c.surfaceAlt)
    }

    @ViewBuilder
    private func stickerContent(_ c: TgColors) -> some View {
        if !recents.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("最近")
                        .font(.system(size: 11))
                        .foregroundColor(c.textTertiary)
                    ForEach(recents, id: \.self) { emoji in
                        stickerButton(emoji, side: 40)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 52)
        }

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(currentPack.emojis, id: \.self) { emoji in
                    stickerButton(emoji, side: 66)
                }
            }
            .padding(10)
        }
        .frame(height: 185)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(StickerStore.packs) { pack in
                    Button {
                        selectedPack = pack.id
                    } label: {
                        Text(pack.emojis.first ?? "🙂")
                            .font(.system(size: 22))
                            .opacity(selectedPack == pack.id ? 1 : 0.55)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(c.background)
    }

    private var filteredGifs: [GifItem] {
        let query = gifQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return StickerStore.gifs }
        return StickerStore.gifs.filter { item in
            item.title.localizedCaseInsensitiveContains(query) ||
                item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @ViewBuilder
    private func gifContent(_ c: TgColors) -> some View {
        TextField("搜索 GIF", text: $gifQuery)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(c.background))
            .padding(.horizontal, 16)

        if !recentGifIds.isEmpty && gifQuery.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("最近")
                        .font(.system(size: 11))
                        .foregroundColor(c.textTertiary)
                    ForEach(recentGifIds, id: \.self) { id in
                        gifThumb(id, side: 42)
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: 54)
        }

        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(filteredGifs) { item in
                    Button {
                        sendGif(item)
                    } label: {
                        VStack(spacing: 4) {
                            AnimatedImageView(url: StickerStore.gifURL(item.file), token: nil)
                                .frame(width: 72, height: 72)
                            Text(item.title)
                                .font(.system(size: 11))
                                .foregroundColor(c.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(height: 185)
    }

    private var currentPack: StickerPack {
        StickerStore.packs.first { $0.id == selectedPack } ?? StickerStore.packs[0]
    }

    private func stickerButton(_ emoji: String, side: CGFloat) -> some View {
        Button {
            sendSticker(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: side * 0.86))
                .frame(width: side + 10, height: side + 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    private func gifThumb(_ id: String, side: CGFloat) -> some View {
        Group {
            if let item = StickerStore.gifs.first(where: { $0.id == id }) {
                Button {
                    sendGif(item)
                } label: {
                    AnimatedImageView(url: StickerStore.gifURL(item.file), token: nil)
                        .frame(width: side, height: side)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sendSticker(_ emoji: String) {
        guard let data = StickerStore.stickerPNG(emoji) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sticker-\(UUID().uuidString).png")
        try? data.write(to: url)
        StickerStore.addRecent(emoji)
        recents = StickerStore.recent()
        app.sendMedia(
            chatId: chatId,
            fileURL: url,
            kind: "sticker",
            mime: "image/png",
            name: "\(emoji).png",
            caption: "",
            width: 240,
            height: 240
        )
    }

    private func sendGif(_ item: GifItem) {
        guard let data = StickerStore.gifData(item.id) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gif-\(UUID().uuidString).gif")
        try? data.write(to: url)
        StickerStore.addRecentGif(item.id)
        recentGifIds = StickerStore.recentGifs()
        app.sendMedia(
            chatId: chatId,
            fileURL: url,
            kind: "gif",
            mime: "image/gif",
            name: "\(item.id).gif",
            caption: "",
            width: 96,
            height: 96
        )
    }
}
