import SwiftUI
import UIKit

// MARK: - Motion tokens
//
// One place for every duration/spring used across the app. Screens should not
// invent their own timings; they pick a token and let `Motion.animation`
// degrade it when Reduce Motion is on.

enum Motion {
    /// Button presses, tiny state flips.
    static let quick = Animation.spring(response: 0.26, dampingFraction: 0.86)
    /// Default for layout, insertions and panel movement.
    static let standard = Animation.spring(response: 0.36, dampingFraction: 0.87)
    /// Larger surfaces: sheets, media, navigation-adjacent movement.
    static let gentle = Animation.spring(response: 0.48, dampingFraction: 0.9)
    /// Playful accent used sparingly (send button, reactions).
    static let bouncy = Animation.spring(response: 0.42, dampingFraction: 0.7)
    /// Short opacity-only crossfade.
    static let fade = Animation.easeOut(duration: 0.16)
    /// Layout changes inside a list (reordering, folder pill).
    static let layout = Animation.spring(response: 0.34, dampingFraction: 0.88)

    /// Reduce Motion maps everything onto a short crossfade so state changes
    /// still read, but nothing travels across the screen.
    static func animation(_ base: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : base
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Press feedback

/// Subtle press state for cards and rows: scales down slightly and dims.
/// With Reduce Motion the scale is dropped and only opacity changes.
struct MotionPressStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    var pressedOpacity: Double = 0.92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : scale)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.quick,
                value: configuration.isPressed
            )
    }
}

/// Press feedback for icon-only buttons: no layout change, just a gentle dip.
struct MotionIconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.9 : 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.1) : Motion.quick,
                value: configuration.isPressed
            )
    }
}

// MARK: - Transitions

extension AnyTransition {
    /// Slides a surface in from an edge and fades out. Reduce Motion collapses
    /// this to a pure crossfade so nothing moves.
    static func motionSlide(
        reduceMotion: Bool,
        edge: Edge = .bottom,
        distance: CGFloat = 16
    ) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        let dx: CGFloat = edge == .leading ? distance : (edge == .trailing ? -distance : 0)
        let dy: CGFloat = edge == .top ? -distance : (edge == .bottom ? distance : 0)
        return .asymmetric(
            insertion: .offset(x: dx, y: dy).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Import/insert transition for a new message: small lift + fade.
    static func motionMessage(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .offset(y: 10).combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Crossfade used by tabs and media swaps.
    static var motionCrossfade: AnyTransition {
        .opacity
    }
}

// MARK: - Cached text helpers
//
// `formattedText` and bubble width measurement used to run markdown parsing,
// NSDataDetector and CoreText measurement on every layout pass. Results are
// memoised so the main thread only pays once per unique string.

private final class AttributedBox: NSObject {
    let value: AttributedString
    init(_ value: AttributedString) {
        self.value = value
    }
}

enum TextFormatCache {
    private static let cache: NSCache<NSString, AttributedBox> = {
        let cache = NSCache<NSString, AttributedBox>()
        cache.countLimit = 600
        return cache
    }()

    private static let widthCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1200
        return cache
    }()

    static func cached(_ text: String) -> AttributedString? {
        cache.object(forKey: text as NSString)?.value
    }

    static func store(_ text: String, _ value: AttributedString) {
        cache.setObject(AttributedBox(value), forKey: text as NSString)
    }

    static func cachedWidth(key: String) -> CGFloat? {
        guard let number = widthCache.object(forKey: key as NSString) else { return nil }
        return CGFloat(number.doubleValue)
    }

    static func storeWidth(key: String, value: CGFloat) {
        widthCache.setObject(NSNumber(value: Double(value)), forKey: key as NSString)
    }
}
