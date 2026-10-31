import SwiftUI
import UIKit

// MARK: - Sticker store

struct StickerPack: Identifiable {
    let id: String
    let title: String
    let emojis: [String]
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

    private static let recentKey = "sticker.recent"
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
}

// MARK: - Sticker panel

struct StickerPanel: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    let chatId: String

    @State private var selectedPack = "faces"
    @State private var recents: [String] = StickerStore.recent()

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
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
            .frame(height: 190)

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
        .background(c.surfaceAlt)
    }

    private var currentPack: StickerPack {
        StickerStore.packs.first { $0.id == selectedPack } ?? StickerStore.packs[0]
    }

    private func stickerButton(_ emoji: String, side: CGFloat) -> some View {
        Button {
            send(emoji)
        } label: {
            Text(emoji)
                .font(.system(size: side * 0.86))
                .frame(width: side + 10, height: side + 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    private func send(_ emoji: String) {
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
}
