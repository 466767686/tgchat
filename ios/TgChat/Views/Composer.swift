import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct PickedMedia: Identifiable {
    let id = UUID()
    var kind: String            // image | video
    var name: String
    var mime: String
    var width: Int?
    var height: Int?
    var durationMs: Int?
    var image: UIImage?
    var originalData: Data?
    var videoURL: URL?
}

private let emojiList: [String] = [
    "😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇",
    "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚",
    "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🥳",
    "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖",
    "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯",
    "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗", "🤔",
    "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🙄", "😯", "😦",
    "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵", "🤐", "🥴",
    "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "😈", "👿",
    "👍", "👎", "👏", "🙌", "🤝", "🙏", "💪", "✌️", "🤞", "👌",
    "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❣️",
    "🎉", "🎊", "🔥", "⭐️", "✨", "💯", "✅", "❌", "⚡️", "🌙",
]

struct ChatComposer: View {
    let chatId: String
    @Binding var draft: String

    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var showAttachMenu = false
    @State private var showPhotoPicker = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFilePicker = false
    @State private var pickedItems: [PickedMedia] = []
    @State private var showMediaCompose = false
    @State private var showEmoji = false
    @State private var showStickers = false
    @StateObject private var recorder = VoiceRecorder()

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        VStack(spacing: 0) {
            if let progress = app.uploadProgress {
                HStack(spacing: 8) {
                    Text(app.uploadName ?? "上传中")
                        .font(.system(size: 11))
                        .foregroundColor(c.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(c.accent)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                ProgressView(value: progress)
                    .tint(c.accent)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 2)
            }

            if app.uploadFailed {
                HStack(spacing: 12) {
                    Text("上传失败")
                        .font(.system(size: 12))
                        .foregroundColor(c.danger)
                    Spacer()
                    Button("重试") { app.retryUpload() }
                        .font(.system(size: 12, weight: .semibold))
                    Button("取消") { app.cancelUpload() }
                        .font(.system(size: 12))
                        .foregroundColor(c.textSecondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }

            if showStickers {
                StickerPanel(chatId: chatId)
                    .environmentObject(app)
            }

            if showEmoji {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 6) {
                        ForEach(emojiList, id: \.self) { emoji in
                            Text(emoji)
                                .font(.system(size: 26))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .onTapGesture { draft += emoji }
                        }
                    }
                    .padding(10)
                }
                .frame(height: 220)
                .background(c.surfaceAlt)
            }

            if recorder.isRecording {
                HStack(spacing: 10) {
                    Circle()
                        .fill(c.danger)
                        .frame(width: 9, height: 9)
                    Text(recorderTime(recorder.duration))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(c.textPrimary)

                    HStack(spacing: 2) {
                        ForEach(0..<recentLevels.count, id: \.self) { index in
                            Capsule()
                                .fill(c.accent)
                                .frame(width: 2.5, height: max(3, recentLevels[index] * 26))
                        }
                    }
                    .frame(height: 26)

                    Spacer()

                    Button("取消") { recorder.cancel() }
                        .font(.system(size: 13))
                        .foregroundColor(c.textSecondary)

                    Button {
                        sendVoice()
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(c.accent))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(c.header)
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        showAttachMenu = true
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(c.textSecondary)
                            .frame(width: 34, height: 34)
                    }

                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .font(.system(size: 16))
                        .foregroundColor(c.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 20).fill(c.surfaceAlt))
                        .onChange(of: draft) { newValue in
                            if !newValue.isEmpty { app.sendTyping() }
                        }

                    Button {
                        showStickers.toggle()
                        if showStickers { showEmoji = false }
                    } label: {
                        Image(systemName: "face.dashed")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(showStickers ? c.accent : c.textSecondary)
                            .frame(width: 30, height: 34)
                    }

                    Button {
                        showEmoji.toggle()
                        if showEmoji { showStickers = false }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(showEmoji ? c.accent : c.textSecondary)
                            .frame(width: 30, height: 34)
                    }

                    if draft.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            showEmoji = false
                            showStickers = false
                            recorder.start()
                        } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(c.accent))
                        }
                        .disabled(app.uploadProgress != nil)
                    } else {
                        Button {
                            let text = draft
                            draft = ""
                            Task { await app.sendMessage(text, chatId: chatId) }
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 42, height: 42)
                                .background(Circle().fill(c.accent))
                        }
                        .disabled(app.uploadProgress != nil)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(c.header)
            }
        }
        .confirmationDialog("发送", isPresented: $showAttachMenu, titleVisibility: .hidden) {
            Button("照片或视频") { showPhotoPicker = true }
            Button("文件") { showFilePicker = true }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $pickerItems,
            maxSelectionCount: 10,
            matching: .any(of: [.images, .videos]),
            photoLibrary: .shared()
        )
        .onChange(of: pickerItems) { items in
            Task { await loadPicked(items) }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls { importFile(url) }
            }
        }
        .sheet(isPresented: $showMediaCompose) {
            MediaComposeSheet(items: pickedItems, chatId: chatId)
                .environmentObject(app)
        }
    }

    private var recentLevels: [CGFloat] {
        Array(recorder.levels.suffix(26))
    }

    private func recorderTime(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func sendVoice() {
        guard let (url, ms) = recorder.stop() else { return }
        app.sendMedia(
            chatId: chatId,
            fileURL: url,
            kind: "voice",
            mime: "audio/mp4",
            name: "voice.m4a",
            caption: "",
            durationMs: ms
        )
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        var result: [PickedMedia] = []
        for item in items {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let video = try? await item.loadTransferable(type: VideoTransferable.self) {
                    let asset = AVURLAsset(url: video.url)
                    let duration = CMTimeGetSeconds(asset.duration)
                    let size = await videoSize(asset)
                    let ext = video.url.pathExtension.lowercased()
                    result.append(
                        PickedMedia(
                            kind: "video",
                            name: "video." + (ext.isEmpty ? "mov" : ext),
                            mime: ext == "mp4" ? "video/mp4" : "video/quicktime",
                            width: Int(size.width),
                            height: Int(size.height),
                            durationMs: Int(duration * 1000),
                            videoURL: video.url
                        )
                    )
                }
            } else if let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) {
                result.append(
                    PickedMedia(
                        kind: "image",
                        name: "photo.jpg",
                        mime: "image/jpeg",
                        width: Int(image.size.width),
                        height: Int(image.size.height),
                        image: image,
                        originalData: data
                    )
                )
            }
        }
        pickerItems = []
        guard !result.isEmpty else { return }
        pickedItems = result
        showMediaCompose = true
    }

    private func importFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        app.sendMedia(
            chatId: chatId,
            fileURL: copy,
            kind: "file",
            mime: mime,
            name: url.lastPathComponent,
            caption: ""
        )
    }

    private func videoSize(_ asset: AVURLAsset) async -> CGSize {
        let tracks = (try? await asset.loadTracks(withMediaType: .video)) ?? []
        guard let track = tracks.first else { return .zero }
        let size = (try? await track.load(.naturalSize)) ?? .zero
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let transformed = size.applying(transform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }
}

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return VideoTransferable(url: copy)
        }
    }
}

struct MediaComposeSheet: View {
    let items: [PickedMedia]
    let chatId: String

    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var caption = ""
    @State private var original = false
    @State private var sending = false

    var body: some View {
        let c = TgColors(dark: scheme == .dark)

        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            thumbnail(item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 160)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("添加说明…", text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(c.surfaceAlt))
                    Toggle("发送原图（不压缩）", isOn: $original)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .padding(.top, 12)
            .background(c.background)
            .navigationTitle("发送 \(items.count) 项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        send()
                    }
                    .disabled(sending)
                }
            }
        }
    }

    private func thumbnail(_ item: PickedMedia) -> some View {
        Group {
            if let image = item.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.black.opacity(0.1)
                    Image(systemName: "video.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 24))
                }
            }
        }
        .frame(width: 130, height: 150)
        .clipped()
        .cornerRadius(12)
    }

    private func send() {
        sending = true
        for (index, item) in items.enumerated() {
            let text = index == 0 ? caption : ""
            if item.kind == "image" {
                guard let image = item.image else { continue }
                let data: Data
                if original, let raw = item.originalData {
                    data = raw
                } else {
                    data = compress(image) ?? item.originalData ?? Data()
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(UUID().uuidString).jpg")
                try? data.write(to: url)
                app.sendMedia(
                    chatId: chatId,
                    fileURL: url,
                    kind: "image",
                    mime: "image/jpeg",
                    name: "photo.jpg",
                    caption: text,
                    width: item.width,
                    height: item.height
                )
            } else if let videoURL = item.videoURL {
                app.sendMedia(
                    chatId: chatId,
                    fileURL: videoURL,
                    kind: "video",
                    mime: item.mime,
                    name: item.name,
                    caption: text,
                    width: item.width,
                    height: item.height,
                    durationMs: item.durationMs
                )
            }
        }
        dismiss()
    }

    private func compress(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.72) -> Data? {
        let largest = max(image.size.width, image.size.height)
        guard largest > maxDimension else { return image.jpegData(compressionQuality: quality) }
        let scale = maxDimension / largest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
