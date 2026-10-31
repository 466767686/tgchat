import SwiftUI

struct AvatarView: View {
    let name: String
    let colorHex: String
    var size: CGFloat = 54
    var online: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: colorHex).opacity(0.72), Color(hex: colorHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundColor(.white)
                )
            if online {
                Circle()
                    .fill(Color(hex: "#4CD964"))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 1, y: 1)
            }
        }
    }

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "?" }
        let parts = trimmed.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            let first = parts[0].first.map(String.init) ?? ""
            let second = parts[1].first.map(String.init) ?? ""
            return (first + second).uppercased()
        }
        return String(trimmed.prefix(1)).uppercased()
    }
}

struct BubbleShape: Shape {
    let isOut: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let tail: CGFloat = 8
        var path = Path()
        let body = CGRect(
            x: isOut ? 0 : tail,
            y: 0,
            width: max(1, rect.width - tail),
            height: rect.height
        )
        path.addRoundedRect(in: body, cornerSize: CGSize(width: radius, height: radius))

        let baseY = max(0, rect.height - 11)
        if isOut {
            path.move(to: CGPoint(x: body.maxX - 1, y: baseY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: body.maxX - 1, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: body.minX + 1, y: baseY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: body.minX + 1, y: rect.maxY))
        }
        return path
    }
}

struct MessageBubbleView: View {
    let message: Message
    let isOut: Bool
    let showAuthor: Bool
    let readByPeer: Bool
    let colors: TgColors
    var showViews: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            if isOut { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 3) {
                if let reply = message.replyTo {
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(Color(hex: message.senderColor))
                            .frame(width: 2.5)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reply.senderName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(colors.accent)
                            Text(reply.text.isEmpty ? "消息" : reply.text)
                                .font(.system(size: 12))
                                .foregroundColor(colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.06)))
                    .padding(.bottom, 2)
                }

                if let forwarded = message.forwardedFrom {
                    Text("转发自 \(forwarded)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(colors.accent)
                        .padding(.bottom, 2)
                }

                if showAuthor {
                    Text(message.senderName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(Color(hex: message.senderColor))
                }
                if message.deleted {
                    Text("消息已删除")
                        .font(.system(size: 15))
                        .italic()
                        .foregroundColor(colors.textTertiary)
                } else {
                    Text(formattedText(message.text))
                        .font(.system(size: 16))
                        .foregroundColor(isOut ? colors.bubbleOutText : colors.bubbleInText)
                        .tint(colors.accent)
                        .frame(maxWidth: 280, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 3) {
                    if message.editedAt != nil {
                        Text("已编辑")
                            .font(.system(size: 10))
                            .foregroundColor(colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(formatTime(message.createdAt))
                        .font(.system(size: 11))
                        .foregroundColor(colors.textTertiary)
                    if showViews, let views = message.views {
                        HStack(spacing: 2) {
                            Image(systemName: "eye")
                                .font(.system(size: 9))
                            Text("\(views)")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(colors.textTertiary)
                    }
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
            }
            .padding(.leading, isOut ? 11 : 19)
            .padding(.trailing, isOut ? 19 : 11)
            .padding(.vertical, 7)
            .background(BubbleShape(isOut: isOut).fill(isOut ? colors.bubbleOut : colors.bubbleIn))
            if !isOut { Spacer(minLength: 44) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1.5)
    }
}

struct DateChipView: View {
    let label: String
    let colors: TgColors

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(colors.dateChip))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String
    let colors: TgColors

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 34))
                .foregroundColor(colors.textTertiary)
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(colors.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black.opacity(0.82)))
            .padding(.bottom, 30)
    }
}
