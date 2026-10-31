import AVFoundation
import Speech
import SwiftUI

// MARK: - Recorder

final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0
    @Published var levels: [CGFloat] = []

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return }
        recorder.isMeteringEnabled = true
        recorder.record()

        self.recorder = recorder
        self.fileURL = url
        date0 = Date()

        duration = 0
        levels = []
        isRecording = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.recorder else { return }
            self.duration = Date().timeIntervalSince(self.date0)
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0.05, min(1, (power + 50) / 50))
            self.levels.append(CGFloat(normalized))
            if self.levels.count > 60 { self.levels.removeFirst() }
        }
    }

    private var date0 = Date()

    /// Stops and returns the file plus duration in ms.
    func stop() -> (URL, Int)? {
        guard isRecording else { return nil }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false

        defer {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            recorder = nil
        }
        guard let url = fileURL else { return nil }
        fileURL = nil
        if duration < 0.5 {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (url, Int(duration * 1000))
    }

    func cancel() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Voice message bubble

struct VoiceMessageView: View {
    let message: Message
    let media: Media
    let isOut: Bool
    let colors: TgColors
    let token: String?

    @State private var downloading = false
    @State private var playing = false
    @State private var localURL: URL?
    @State private var player: AVAudioPlayer?
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @State private var rate: Float = 1.0
    @State private var transcription: String?
    @State private var transcribing = false

    private var bars: [CGFloat] {
        var seed = UInt64(bitPattern: Int64(message.id.hashValue))
        var values: [CGFloat] = []
        for _ in 0..<28 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let v = CGFloat((seed >> 33) % 100) / 100
            values.append(0.25 + v * 0.75)
        }
        return values
    }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(colors.accent)
                        .frame(width: 36, height: 36)
                    if downloading {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(0..<bars.count, id: \.self) { index in
                        let played = Double(index) / Double(bars.count) <= progress
                        Capsule()
                            .fill(played ? colors.accent : colors.textTertiary.opacity(0.5))
                            .frame(width: 2.4, height: max(4, bars[index] * 22))
                    }
                }
                .frame(height: 22)

                HStack(spacing: 8) {
                    Text(durationText)
                        .font(.system(size: 11))
                        .foregroundColor(colors.textTertiary)

                    Button {
                        rate = rate >= 2.0 ? 1.0 : (rate >= 1.5 ? 2.0 : 1.5)
                        if playing {
                            player?.enableRate = true
                            player?.rate = rate
                        }
                    } label: {
                        Text(String(format: "%.1fx", rate))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(colors.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(colors.accent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        toggleTranscription()
                    } label: {
                        if transcribing {
                            ProgressView().scaleEffect(0.5).frame(width: 18, height: 14)
                        } else {
                            Image(systemName: transcription == nil ? "text.bubble" : "text.bubble.fill")
                                .font(.system(size: 11))
                                .foregroundColor(colors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if let transcription = transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(.system(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 210, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 2)
        .onDisappear {
            stopPlayback()
        }
    }

    private var durationText: String {
        if playing || progress > 0 {
            let total = Double(media.durationMs ?? 0) / 1000
            return String(format: "%@ / %@", formatSeconds(total * progress), formatSeconds(total))
        }
        return formatSeconds(Double(media.durationMs ?? 0) / 1000)
    }

    private func formatSeconds(_ value: Double) -> String {
        let seconds = max(0, Int(value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func togglePlayback() {
        if playing {
            stopPlayback()
            return
        }
        if let localURL = localURL {
            play(localURL)
            return
        }
        Task {
            if let file = await ensureLocal() {
                await MainActor.run { play(file) }
            }
        }
    }

    private func ensureLocal() async -> URL? {
        if let localURL = localURL { return localURL }
        guard let url = APIClient.shared.mediaURL(media.url) else { return nil }
        await MainActor.run { downloading = true }
        defer { Task { @MainActor in downloading = false } }
        var request = URLRequest(url: url)
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(media.id).m4a")
        try? data.write(to: file)
        await MainActor.run { localURL = file }
        return file
    }

    private func toggleTranscription() {
        if transcription != nil {
            transcription = nil
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    transcription = "未授权语音识别"
                }
                return
            }
            Task {
                guard let file = await ensureLocal() else { return }
                await MainActor.run { transcribing = true }
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")) ?? SFSpeechRecognizer()
                let request = SFSpeechURLRecognitionRequest(url: file)
                request.shouldReportPartialResults = false
                recognizer?.recognitionTask(with: request) { result, error in
                    DispatchQueue.main.async {
                        if let result = result, result.isFinal {
                            transcription = result.bestTranscription.formattedString
                            transcribing = false
                        } else if error != nil {
                            transcription = "转写失败"
                            transcribing = false
                        }
                    }
                }
            }
        }
    }

    private func play(_ url: URL) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let audio = try? AVAudioPlayer(contentsOf: url) else { return }
        audio.enableRate = true
        audio.rate = rate
        audio.prepareToPlay()
        audio.play()
        player = audio
        playing = true
        progress = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            guard audio.duration > 0 else { return }
            progress = audio.currentTime / audio.duration
            if !audio.isPlaying {
                stopPlayback()
            }
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playing = false
        progress = 0
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
