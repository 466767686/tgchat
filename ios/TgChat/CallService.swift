import AVFoundation
import Foundation
import WebRTC

enum CallState: Equatable {
    case idle
    case outgoing
    case incoming
    case connecting
    case active
    case ended(String)

    var isBusy: Bool {
        switch self {
        case .idle, .ended: return false
        default: return true
        }
    }
}

final class CallService: NSObject, ObservableObject {
    static let shared = CallService()

    @Published var state: CallState = .idle
    @Published var peerName = ""
    @Published var chatId: String?
    @Published var micMuted = false
    @Published var speakerOn = true
    @Published var duration: TimeInterval = 0
    @Published var videoEnabled = false
    @Published var remoteVideoTrack: RTCVideoTrack?
    @Published var localSession: AVCaptureSession?

    var realtime: RealtimeClient?

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var pendingCandidates: [RTCIceCandidate] = []
    private var pendingOfferSdp: String?
    private var durationTimer: Timer?
    private var isCaller = false
    private var startedAt: Date?
    private var videoSource: RTCVideoSource?
    private var capturer: RTCCameraVideoCapturer?

    private let iceServers = [
        RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
        RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
    ]

    // MARK: - Lifecycle

    func startCall(chatId: String, peerName: String, video: Bool = false) {
        guard !state.isBusy else { return }
        self.chatId = chatId
        self.peerName = peerName
        self.videoEnabled = video
        isCaller = true
        state = .outgoing
        duration = 0

        setupAudioSession()
        guard let pc = makePeerConnection() else {
            end("无法初始化通话")
            return
        }
        addLocalAudio(to: pc)
        addLocalVideo(to: pc)

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        pc.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp, error == nil else {
                self?.end("创建通话失败")
                return
            }
            pc.setLocalDescription(sdp) { [weak self] error in
                guard error == nil else {
                    self?.end("创建通话失败")
                    return
                }
                self?.send([
                    "type": "call.invite",
                    "chatId": chatId,
                    "sdp": sdp.sdp,
                    "video": video,
                ])
            }
        }
    }

    func accept() {
        guard case .incoming = state, let sdp = pendingOfferSdp else { return }
        state = .connecting
        setupAudioSession()

        guard let pc = makePeerConnection() else {
            end("无法接听")
            return
        }
        addLocalAudio(to: pc)
        addLocalVideo(to: pc)

        let description = RTCSessionDescription(type: .offer, sdp: sdp)
        pc.setRemoteDescription(description) { [weak self] error in
            guard let self = self, error == nil else {
                self?.end("接听失败")
                return
            }
            self.flushCandidates()
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            pc.answer(for: constraints) { sdp, error in
                guard let sdp = sdp, error == nil else {
                    self.end("接听失败")
                    return
                }
                pc.setLocalDescription(sdp) { [weak self] error in
                    guard error == nil else {
                        self?.end("接听失败")
                        return
                    }
                    self?.send([
                        "type": "call.answer",
                        "chatId": self?.chatId ?? "",
                        "sdp": sdp.sdp,
                    ])
                    DispatchQueue.main.async {
                        self?.markActive()
                    }
                }
            }
        }
    }

    func reject() {
        send(["type": "call.reject", "chatId": chatId ?? ""])
        end("已拒绝")
    }

    func hangup() {
        send(["type": "call.hangup", "chatId": chatId ?? ""])
        end("通话已结束")
    }

    func toggleMute() {
        micMuted.toggle()
        localAudioTrack?.isEnabled = !micMuted
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    func reset() {
        state = .idle
        duration = 0
        peerName = ""
        chatId = nil
        micMuted = false
    }

    // MARK: - Signaling

    func handleSignal(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        switch type {
        case "call.invite":
            guard !state.isBusy else {
                send(["type": "call.reject", "chatId": payload["chatId"] as? String ?? ""])
                return
            }
            chatId = payload["chatId"] as? String
            peerName = payload["fromName"] as? String ?? "对方"
            pendingOfferSdp = payload["sdp"] as? String
            videoEnabled = payload["video"] as? Bool ?? false
            isCaller = false
            state = .incoming

        case "call.answer":
            guard let sdp = payload["sdp"] as? String, let pc = peerConnection else { return }
            let description = RTCSessionDescription(type: .answer, sdp: sdp)
            pc.setRemoteDescription(description) { [weak self] error in
                guard error == nil else {
                    self?.end("连接失败")
                    return
                }
                self?.flushCandidates()
                DispatchQueue.main.async {
                    self?.markActive()
                }
            }

        case "call.ice":
            guard let candidate = payload["candidate"] as? String else { return }
            let ice = RTCIceCandidate(
                sdp: candidate,
                sdpMLineIndex: Int32(payload["sdpMLineIndex"] as? Int ?? 0),
                sdpMid: payload["sdpMid"] as? String
            )
            if let pc = peerConnection, pc.remoteDescription != nil {
                pc.add(ice)
            } else {
                pendingCandidates.append(ice)
            }

        case "call.hangup":
            end("对方已挂断")
        case "call.reject":
            end("对方已拒绝")
        default:
            break
        }
    }

    // MARK: - Internals

    private func makePeerConnection() -> RTCPeerConnection? {
        if factory == nil {
            RTCInitializeSSL()
            let encoder = RTCDefaultVideoEncoderFactory()
            let decoder = RTCDefaultVideoDecoderFactory()
            factory = RTCPeerConnectionFactory(encoderFactory: encoder, decoderFactory: decoder)
        }
        guard let factory = factory else { return nil }

        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.continualGatheringPolicy = .gatherContinually

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["DtlsSrtpKeyAgreement": "true"],
            optionalConstraints: nil
        )
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            return nil
        }
        peerConnection = pc
        pendingCandidates.removeAll()
        return pc
    }

    private func addLocalAudio(to pc: RTCPeerConnection) {
        guard let factory = factory else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let source = factory.audioSource(with: constraints)
        let track = factory.audioTrack(with: source, trackId: "audio0")
        pc.add(track, streamIds: ["stream0"])
        localAudioTrack = track
    }

    private func addLocalVideo(to pc: RTCPeerConnection) {
        guard videoEnabled, let factory = factory else { return }
        let source = factory.videoSource()
        videoSource = source
        let capturer = RTCCameraVideoCapturer(delegate: source)
        self.capturer = capturer

        let devices = RTCCameraVideoCapturer.captureDevices()
        if let device = devices.first(where: { $0.position == .front }) ?? devices.first,
           let format = RTCCameraVideoCapturer.supportedFormats(for: device).last {
            let maxFps = format.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 30
            capturer.startCapture(with: device, format: format, fps: Int(min(30, maxFps)))
            localSession = capturer.captureSession
        }

        let track = factory.videoTrack(with: source, trackId: "video0")
        pc.add(track, streamIds: ["stream0"])
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    private func markActive() {
        state = .active
        startedAt = Date()
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.startedAt else { return }
            self.duration = Date().timeIntervalSince(start)
        }
    }

    private func send(_ payload: [String: Any]) {
        realtime?.sendRaw(payload)
    }

    private func flushCandidates() {
        guard let pc = peerConnection else { return }
        for candidate in pendingCandidates {
            pc.add(candidate)
        }
        pendingCandidates.removeAll()
    }

    private func end(_ reason: String) {
        durationTimer?.invalidate()
        durationTimer = nil
        capturer?.stopCapture()
        capturer = nil
        videoSource = nil
        localSession = nil
        remoteVideoTrack = nil
        videoEnabled = false
        peerConnection?.close()
        peerConnection = nil
        localAudioTrack = nil
        startedAt = nil
        pendingOfferSdp = nil
        state = .ended(reason)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension CallService: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        guard let video = stream.videoTracks.first else { return }
        DispatchQueue.main.async {
            self.remoteVideoTrack = video
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            if state != .active {
                DispatchQueue.main.async { self.markActive() }
            }
        case .failed:
            DispatchQueue.main.async { self.end("网络连接失败") }
        case .disconnected:
            break
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        send([
            "type": "call.ice",
            "chatId": chatId ?? "",
            "candidate": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": Int(candidate.sdpMLineIndex),
        ])
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
