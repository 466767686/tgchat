import SwiftUI

/// 伪装成计算器的锁屏。输入解锁密码后按 "=" 进入聊天界面。
struct CalculatorView: View {
    @EnvironmentObject private var app: AppState

    @State private var display = "0"
    @State private var accumulator: Double?
    @State private var pending: String?
    @State private var resetOnNextDigit = false

    private enum KeyKind { case digit, function, operation }

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 14
            let keyWidth = (proxy.size.width - 40 - gap * 3) / 4

            VStack(spacing: gap) {
                Spacer(minLength: 0)

                Text(display)
                    .font(.system(size: 76, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 18)

                row(width: keyWidth, gap: gap, keys: [
                    ("AC", .function), ("±", .function), ("%", .function), ("÷", .operation),
                ])
                row(width: keyWidth, gap: gap, keys: [
                    ("7", .digit), ("8", .digit), ("9", .digit), ("×", .operation),
                ])
                row(width: keyWidth, gap: gap, keys: [
                    ("4", .digit), ("5", .digit), ("6", .digit), ("−", .operation),
                ])
                row(width: keyWidth, gap: gap, keys: [
                    ("1", .digit), ("2", .digit), ("3", .digit), ("+", .operation),
                ])

                HStack(spacing: gap) {
                    key("0", .digit, width: keyWidth * 2 + gap, height: 74)
                    key(".", .digit, width: keyWidth, height: 74)
                    key("=", .operation, width: keyWidth, height: 74)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
    }

    private func row(width: CGFloat, gap: CGFloat, keys: [(String, KeyKind)]) -> some View {
        HStack(spacing: gap) {
            ForEach(keys.indices, id: \.self) { index in
                key(keys[index].0, keys[index].1, width: width, height: 74)
            }
        }
    }

    private func key(_ label: String, _ kind: KeyKind, width: CGFloat, height: CGFloat) -> some View {
        Button {
            tap(label, kind)
        } label: {
            Text(label)
                .font(.system(size: 30, weight: .regular))
                .foregroundColor(kind == .function ? .black : .white)
                .frame(width: width, height: height)
                .background(background(for: kind))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func background(for kind: KeyKind) -> Color {
        switch kind {
        case .digit: return Color(hex: "#333333")
        case .function: return Color(hex: "#A5A5A5")
        case .operation: return Color(hex: "#FF9F0A")
        }
    }

    // MARK: - Behaviour

    private func tap(_ label: String, _ kind: KeyKind) {
        switch kind {
        case .digit:
            if label == "." {
                if resetOnNextDigit {
                    display = "0."
                    resetOnNextDigit = false
                } else if !display.contains(".") {
                    display += "."
                }
                return
            }
            if resetOnNextDigit || display == "0" {
                display = label
                resetOnNextDigit = false
            } else if display.count < 12 {
                display += label
            }

        case .function:
            switch label {
            case "AC":
                display = "0"
                accumulator = nil
                pending = nil
                resetOnNextDigit = false
            case "±":
                if display.hasPrefix("-") {
                    display.removeFirst()
                } else if display != "0" {
                    display = "-" + display
                }
            case "%":
                if let value = Double(display) {
                    display = format(value / 100)
                }
            default:
                break
            }

        case .operation:
            if label == "=" {
                unlockIfNeeded()
                evaluate()
            } else {
                commitPending()
                accumulator = Double(display)
                pending = label
                resetOnNextDigit = true
            }
        }
    }

    private func unlockIfNeeded() {
        if display == app.unlockPin {
            withAnimation(.easeInOut(duration: 0.25)) {
                app.unlock()
            }
        }
    }

    private func commitPending() {
        guard let op = pending, let left = accumulator, let right = Double(display) else { return }
        let result = compute(op, left, right)
        display = format(result)
        accumulator = result
        pending = nil
        resetOnNextDigit = true
    }

    private func evaluate() {
        guard let op = pending, let left = accumulator, let right = Double(display) else {
            resetOnNextDigit = true
            return
        }
        let result = compute(op, left, right)
        display = format(result)
        accumulator = nil
        pending = nil
        resetOnNextDigit = true
    }

    private func compute(_ op: String, _ left: Double, _ right: Double) -> Double {
        switch op {
        case "+": return left + right
        case "−": return left - right
        case "×": return left * right
        case "÷": return right == 0 ? Double.nan : left / right
        default: return right
        }
    }

    private func format(_ value: Double) -> String {
        if value.isNaN || value.isInfinite { return "错误" }
        if value == value.rounded(), abs(value) < 1_000_000_000_000 {
            return String(Int(value))
        }
        return String(format: "%.8g", value)
    }
}
