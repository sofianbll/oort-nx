import SwiftUI

/// State-driven curves. Rails use SwiftUI's replacing spring, not queued animations.
public enum Motion {
    private typealias Timing = SeleneTokens.Motion

    public static func transfer(_ reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: Timing.transfer)
    }

    public enum BuildArt: Double {
        case fill = 0.9, stage = 0.8, steps = 0.6, label = 0.4
    }

    public static func buildArt(_ reduced: Bool, _ part: BuildArt) -> Animation? {
        reduced ? nil : .easeInOut(duration: part.rawValue)
    }

    public static let focusIn = Animation.timingCurve(0.22, 1, 0.36, 1, duration: Timing.focusIn)
    public static let focusOut = Animation.timingCurve(0.22, 1, 0.36, 1, duration: Timing.focusOut)

    public static func focus(_ reduced: Bool, entering: Bool = true) -> Animation? {
        reduced ? nil : entering ? focusIn : focusOut
    }

    /// A key goes down at once and comes back with a small overshoot. Nothing moves under Reduce motion.
    public static func press(_ reduced: Bool, down: Bool) -> Animation? {
        reduced ? nil : down ? .linear(duration: Timing.press)
            : .timingCurve(0.3, 1.6, 0.5, 1, duration: Timing.move)
    }

    /// The halftone rising under a focused key.
    public static func dots(_ reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: Timing.slow)
    }

    public enum Rail { case spotlight, collection }

    public static func rail(_ reduced: Bool, _ rail: Rail) -> Animation? {
        reduced ? nil : .spring(response: rail == .spotlight ? 0.32 : 0.18, dampingFraction: 1)
    }

    public static func railOffset(_ position: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(0, position), max(0, maximum))
    }

    public static let screenDuration = Timing.screen
    public static let screen = Animation.timingCurve(0.32, 0.72, 0, 1, duration: screenDuration)

    public static func screen(_ reduced: Bool) -> Animation? {
        reduced ? nil : screen
    }

    public static func overlay(_ reduced: Bool) -> Animation? {
        reduced ? .easeOut(duration: Timing.reducedFade) : focus(false)
    }

    public static func anchoredCard(_ reduced: Bool) -> Animation? {
        overlay(reduced)
    }

    public static func toast(_ reduced: Bool) -> Animation? {
        .easeOut(duration: reduced ? Timing.reducedFade : Timing.toast)
    }

    public static func rowMessage(_ reduced: Bool) -> Animation? {
        reduced ? overlay(true) : .easeOut(duration: Timing.rowMessage)
    }

    public static func detailBand(_ reduced: Bool) -> Animation? {
        reduced ? nil : .timingCurve(0.215, 0.61, 0.355, 1, duration: screenDuration)
    }

    public static func detailArt(_ reduced: Bool) -> Animation? {
        reduced ? overlay(true) : .easeInOut(duration: Timing.detailArt)
    }

    public static func viewer(_ reduced: Bool) -> Animation? {
        reduced ? overlay(true) : .easeOut(duration: Timing.viewer)
    }

    public static func menuIcon(_ reduced: Bool, index: Int) -> Animation? {
        reduced ? overlay(true) : .timingCurve(0.215, 0.61, 0.355, 1, duration: 0.26)
            .delay(Double(index) * 0.025)
    }
}
