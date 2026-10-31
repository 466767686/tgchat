import SwiftUI

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

struct TgColors {
    let dark: Bool

    var accent: Color { Color(hex: dark ? "#6AB3F3" : "#3390EC") }
    var background: Color { Color(hex: dark ? "#0E1621" : "#FFFFFF") }
    var surface: Color { Color(hex: dark ? "#17212B" : "#FFFFFF") }
    var surfaceAlt: Color { Color(hex: dark ? "#232E3C" : "#F1F3F6") }
    var textPrimary: Color { Color(hex: dark ? "#F5F7FA" : "#0F1419") }
    var textSecondary: Color { Color(hex: dark ? "#8A9AA8" : "#707579") }
    var textTertiary: Color { Color(hex: dark ? "#6D7F8E" : "#8E9299") }
    var divider: Color { Color(hex: dark ? "#1C2733" : "#E9EBEE") }
    var bubbleIn: Color { Color(hex: dark ? "#182533" : "#FFFFFF") }
    var bubbleOut: Color { Color(hex: dark ? "#2B5278" : "#EFFDDE") }
    var bubbleInText: Color { Color(hex: dark ? "#F2F5F8" : "#0F1419") }
    var bubbleOutText: Color { Color(hex: dark ? "#FFFFFF" : "#0F1419") }
    var chatBgTop: Color { Color(hex: dark ? "#0B131C" : "#D7E3EE") }
    var chatBgBottom: Color { Color(hex: dark ? "#15212D" : "#EDF2F7") }
    var header: Color { Color(hex: dark ? "#17212B" : "#FFFFFF") }
    var danger: Color { Color(hex: "#E0493E") }
    var dateChip: Color { Color.black.opacity(0.45) }
}

private enum TimeFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let listDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yy"
        return formatter
    }()

    static let headerDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

func formatTime(_ millis: Int64) -> String {
    TimeFormatters.time.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
}

func formatListTime(_ millis: Int64) -> String {
    guard millis > 0 else { return "" }
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return formatTime(millis)
    }
    if calendar.isDateInYesterday(date) {
        return "昨天"
    }
    return TimeFormatters.listDay.string(from: date)
}

func formatDateHeader(_ millis: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "今天" }
    if calendar.isDateInYesterday(date) { return "昨天" }
    return TimeFormatters.headerDay.string(from: date)
}

func formattedText(_ text: String) -> AttributedString {
    if let cached = TextFormatCache.cached(text) {
        return cached
    }
    let result = buildFormattedText(text)
    TextFormatCache.store(text, result)
    return result
}

private func buildFormattedText(_ text: String) -> AttributedString {
    var attributed = (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    )) ?? AttributedString(text)

    // autolink bare URLs
    if attributed.runs.isEmpty {
        return attributed
    }
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    let full = String(attributed.characters)
    let nsRange = NSRange(full.startIndex..<full.endIndex, in: full)
    detector?.enumerateMatches(in: full, options: [], range: nsRange) { result, _, _ in
        guard let result = result, let url = result.url,
              let range = Range(result.range, in: full),
              let attributedRange = Range(range, in: attributed) else { return }
        attributed[attributedRange].link = url
        attributed[attributedRange].underlineStyle = .single
    }
    // highlight @mentions
    let plain = String(attributed.characters)
    if let regex = try? NSRegularExpression(pattern: "@[A-Za-z0-9_.]{2,32}") {
        let nsRange = NSRange(plain.startIndex..<plain.endIndex, in: plain)
        regex.enumerateMatches(in: plain, options: [], range: nsRange) { result, _, _ in
            guard let result = result,
                  let range = Range(result.range, in: plain),
                  let attributedRange = Range(range, in: attributed) else { return }
            attributed[attributedRange].foregroundColor = TgColors(dark: false).accent
            attributed[attributedRange].inlinePresentationIntent = .stronglyEmphasized
        }
    }
    return attributed
}

func isSameDay(_ a: Int64, _ b: Int64) -> Bool {
    let calendar = Calendar.current
    return calendar.isDate(Date(timeIntervalSince1970: Double(a) / 1000), inSameDayAs: Date(timeIntervalSince1970: Double(b) / 1000))
}
