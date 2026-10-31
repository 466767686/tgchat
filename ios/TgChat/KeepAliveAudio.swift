import AVFoundation
import Foundation

/// Keeps the app alive in the background by looping a silent audio file.
/// iOS suspends normal apps shortly after they leave the foreground; an app with
/// the `audio` background mode that is actively playing keeps running, which lets
/// our WebSocket stay connected and local notifications fire immediately.
final class KeepAliveAudio {
    static let shared = KeepAliveAudio()

    private var player: AVAudioPlayer?
    private var running = false

    func start() {
        guard !running else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audio = try AVAudioPlayer(contentsOf: silentFileURL())
            audio.numberOfLoops = -1
            audio.volume = 0.01
            audio.play()
            player = audio
            running = true
        } catch {
            running = false
        }
    }

    func stop() {
        guard running else { return }
        player?.stop()
        player = nil
        running = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func silentFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tgchat-silence.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? silentWave().write(to: url)
        }
        return url
    }

    /// 1 second of silence, 8 kHz mono 16-bit PCM.
    private func silentWave() -> Data {
        let sampleRate: UInt32 = 8000
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let sampleCount = Int(sampleRate)
        let dataSize = sampleCount * Int(channels) * Int(bits / 8)

        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1)
        append16(channels)
        append32(sampleRate)
        append32(sampleRate * UInt32(channels) * UInt32(bits / 8))
        append16(channels * (bits / 8))
        append16(bits)
        append("data")
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
