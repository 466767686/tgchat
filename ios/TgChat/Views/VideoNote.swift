import AVFoundation
import SwiftUI
import UIKit

// MARK: - Camera picker for round video messages

struct VideoNotePicker: UIViewControllerRepresentable {
    let onPicked: (URL) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = ["public.movie"]
        picker.videoMaximumDuration = 15
        picker.videoQuality = .typeMedium
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.cameraDevice = .front
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: VideoNotePicker

        init(_ parent: VideoNotePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                parent.onPicked(url)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Round video message bubble

struct VideoNoteView: View {
    let media: Media
    let token: String?
    let colors: TgColors

    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var progress: Double = 0
    @State private var observer: Any?
    @State private var downloading = false

    private let side: CGFloat = 190

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.12))
                .frame(width: side, height: side)

            if let player = player {
                VideoLayerView(player: player)
                    .frame(width: side, height: side)
                    .clipShape(Circle())
            }

            if downloading {
                ProgressView().tint(.white)
            } else if !playing {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 4)
            }

            Circle()
                .trim(from: 0, to: progress)
                .stroke(colors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: side, height: side)

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9))
                    Text(formatDuration(media.durationMs ?? 0))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(.bottom, 12)
            }
            .frame(width: side, height: side)
        }
        .onTapGesture { toggle() }
        .onAppear { prepare() }
        .onDisappear { stop() }
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = max(0, ms / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func prepare() {
        guard player == nil, let url = APIClient.shared.mediaURL(media.url) else { return }
        var headers: [String: String] = [:]
        if let token = token {
            headers["Authorization"] = "Bearer \(token)"
        }
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { time in
            let total = CMTimeGetSeconds(asset.duration)
            guard total > 0 else { return }
            progress = min(1, CMTimeGetSeconds(time) / total)
            if progress >= 0.999 {
                player.pause()
                playing = false
                player.seek(to: .zero)
                progress = 0
                player.play()
                player.pause()
            }
        }
    }

    private func toggle() {
        guard let player = player else { return }
        if playing {
            player.pause()
            playing = false
        } else {
            if progress >= 0.999 { player.seek(to: .zero) }
            player.play()
            playing = true
        }
    }

    private func stop() {
        player?.pause()
        playing = false
        if let observer = observer {
            player?.removeTimeObserver(observer)
        }
        observer = nil
    }
}

struct VideoLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
