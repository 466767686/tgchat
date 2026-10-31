import SwiftUI

struct CallView: View {
    @ObservedObject private var call = CallService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#22303F"), Color(hex: "#101820")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                AvatarView(name: call.peerName.isEmpty ? "?" : call.peerName, colorHex: "#3390EC", size: 110)

                Text(call.peerName.isEmpty ? "语音通话" : call.peerName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)

                Text(statusText)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.72))

                if case .active = call.state {
                    Text(durationText)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .monospacedDigit()
                }

                Spacer()
                controls
                    .padding(.bottom, 40)
            }
        }
        .onChange(of: call.state) { state in
            if case .ended = state {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    call.reset()
                    dismiss()
                }
            }
        }
    }

    private var statusText: String {
        switch call.state {
        case .idle: return ""
        case .outgoing: return "正在呼叫…"
        case .incoming: return "邀请你进行语音通话"
        case .connecting: return "连接中…"
        case .active: return "通话中"
        case .ended(let reason): return reason
        }
    }

    private var durationText: String {
        let total = Int(call.duration)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    @ViewBuilder
    private var controls: some View {
        switch call.state {
        case .incoming:
            HStack(spacing: 60) {
                callButton(icon: "phone.down.fill", color: Color(hex: "#EB4034"), label: "拒绝") {
                    call.reject()
                }
                callButton(icon: "phone.fill", color: Color(hex: "#34C759"), label: "接听") {
                    call.accept()
                }
            }

        case .outgoing, .connecting, .active:
            HStack(spacing: 44) {
                callButton(
                    icon: call.micMuted ? "mic.slash.fill" : "mic.fill",
                    color: Color.white.opacity(0.16),
                    label: call.micMuted ? "取消静音" : "静音"
                ) {
                    call.toggleMute()
                }
                callButton(
                    icon: call.speakerOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    color: Color.white.opacity(0.16),
                    label: "扬声器"
                ) {
                    call.toggleSpeaker()
                }
                callButton(icon: "phone.down.fill", color: Color(hex: "#EB4034"), label: "挂断") {
                    call.hangup()
                }
            }

        case .ended:
            callButton(icon: "xmark", color: Color.white.opacity(0.16), label: "关闭") {
                call.reset()
            }

        case .idle:
            EmptyView()
        }
    }

    private func callButton(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 66, height: 66)
                    .background(Circle().fill(color))
            }
            .buttonStyle(.plain)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
    }
}
