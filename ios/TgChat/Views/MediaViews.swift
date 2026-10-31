import AVKit
import SwiftUI
import UIKit

// MARK: - Image loading

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

struct RemoteImageView: View {
    let url: URL?
    let token: String?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                ZStack {
                    Color.black.opacity(0.06)
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundColor(.gray)
                }
            } else {
                ZStack {
                    Color.black.opacity(0.06)
                    ProgressView()
                }
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url = url else { return }
        if let cached = ImageCache.shared.image(for: url.absoluteString) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let decoded = UIImage(data: data) else {
            failed = true
            return
        }
        ImageCache.shared.store(decoded, for: url.absoluteString)
        image = decoded
    }
}

// MARK: - Media bubble

struct MediaMessageView: View {
    let message: Message
    let media: Media
    let isOut: Bool
    let readByPeer: Bool
    let colors: TgColors
    let token: String?
    let onOpenImage: (Media) -> Void
    let onOpenVideo: (Media) -> Void

    private var imageSize: CGSize {
        let maxWidth: CGFloat = 240
        let maxHeight: CGFloat = 300
        guard let w = media.width, let h = media.height, w > 0, h > 0 else {
            return CGSize(width: 220, height: 160)
        }
        let ratio = CGFloat(h) / CGFloat(w)
        var width = maxWidth
        var height = width * ratio
        if height > maxHeight {
            height = maxHeight
            width = height / ratio
        }
        return CGSize(width: width, height: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch media.kind {
            case "image", "sticker":
                Button {
                    onOpenImage(media)
                } label: {
                    RemoteImageView(url: mediaURL, token: token)
                        .frame(width: imageSize.width, height: imageSize.height)
                        .clipped()
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            case "gif":
                Button {
                    onOpenImage(media)
                } label: {
                    AnimatedImageView(url: mediaURL, token: token)
                        .frame(width: imageSize.width, height: imageSize.height)
                        .clipped()
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            case "video":
                Button {
                    onOpenVideo(media)
                } label: {
                    ZStack {
                        RemoteImageView(url: nil, token: token)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .background(Color.black.opacity(0.15))
                        VStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white.opacity(0.95))
                            if let duration = media.durationMs, duration > 0 {
                                Text(formatDuration(duration))
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                    }
                    .frame(width: imageSize.width, height: imageSize.height)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
            case "voice":
                VoiceMessageView(
                    message: message,
                    media: media,
                    isOut: isOut,
                    colors: colors,
                    token: token
                )
            default:
                FileAttachmentRow(media: media, isOut: isOut, colors: colors, token: token)
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundColor(isOut ? colors.bubbleOutText : colors.bubbleInText)
                    .padding(.horizontal, 2)
            }

            HStack(spacing: 3) {
                Spacer(minLength: 0)
                Text(formatTime(message.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(colors.textTertiary)
                if isOut {
                    if message.seq == 0 {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textTertiary)
                    } else {
                        HStack(spacing: -3) {
                            Image(systemName: "checkmark")
                            if readByPeer { Image(systemName: "checkmark") }
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(readByPeer ? colors.accent : colors.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(5)
        .background(BubbleShape(isOut: isOut).fill(isOut ? colors.bubbleOut : colors.bubbleIn))
        .frame(maxWidth: 260, alignment: isOut ? .trailing : .leading)
    }

    private var mediaURL: URL? {
        guard let base = APIClient.shared.mediaURL(media.url) else { return nil }
        return base
    }
}

func formatDuration(_ millis: Int) -> String {
    let seconds = max(0, millis / 1000)
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

struct FileAttachmentRow: View {
    let media: Media
    let isOut: Bool
    let colors: TgColors
    let token: String?

    @State private var downloading = false
    @State private var progress: Double = 0
    @State private var localFile: URL?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 22))
                    .foregroundColor(isOut ? colors.bubbleOutText : colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isOut ? colors.bubbleOutText : colors.bubbleInText)
                        .lineLimit(1)
                    Text(media.sizeText)
                        .font(.system(size: 11))
                        .foregroundColor(colors.textTertiary)
                }
            }

            if let localFile = localFile {
                ShareLink(item: localFile) {
                    Label("保存 / 分享", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13))
                }
            } else if downloading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 180)
            } else {
                Button {
                    Task { await download() }
                } label: {
                    Label("下载", systemImage: "arrow.down.circle")
                        .font(.system(size: 13))
                }
            }

            if let errorText = errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundColor(colors.danger)
            }
        }
        .padding(.vertical, 2)
    }

    private func download() async {
        guard let url = APIClient.shared.mediaURL(media.url) else { return }
        downloading = true
        progress = 0
        errorText = nil
        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let name = media.displayName.isEmpty ? "file" : media.displayName
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination)
            localFile = destination
        } catch {
            errorText = "下载失败"
        }
        downloading = false
    }
}

// MARK: - Full screen viewers

struct ImageViewerSheet: View {
    let media: Media
    let token: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RemoteImageView(url: APIClient.shared.mediaURL(media.url), token: token, contentMode: .fit)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding()
                }
                Spacer()
                if let name = media.name {
                    Text(name)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 20)
                }
            }
        }
    }
}

struct VideoPlayerSheet: View {
    let media: Media
    let token: String?
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear {
            guard let url = APIClient.shared.mediaURL(media.url) else { return }
            var headers: [String: String] = [:]
            if let token = token {
                headers["Authorization"] = "Bearer \(token)"
            }
            let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
        }
        .onDisappear {
            player?.pause()
        }
    }
}
