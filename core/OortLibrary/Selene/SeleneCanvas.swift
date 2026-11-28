import Foundation

/// Selene's 1920x1080 design canvas. Lengths are written in canvas units and
/// multiplied by `scale`, which follows the smaller window axis.
public struct SeleneCanvas: Equatable {
    public static let design = CGSize(width: 1920, height: 1080)

    public let size: CGSize
    /// The player's interface size: every unit grows, the window and the 16:9 stage do not.
    public let zoom: CGFloat

    public init(size: CGSize, zoom: CGFloat = 1) {
        self.size = CGSize(width: max(size.width, 0), height: max(size.height, 0))
        self.zoom = InterfaceZoom.clamped(zoom)
    }

    private var fit: CGFloat {
        min(size.width / Self.design.width, size.height / Self.design.height)
    }

    public var scale: CGFloat { fit * zoom }

    /// The 16:9 stage, `design` scaled uniformly, centred inside `size`.
    public var stageSize: CGSize {
        CGSize(width: Self.design.width * fit, height: Self.design.height * fit)
    }

    public var stageOrigin: CGPoint {
        let stage = stageSize
        return CGPoint(x: (size.width - stage.width) / 2, y: (size.height - stage.height) / 2)
    }

    public func u(_ value: CGFloat) -> CGFloat {
        value * scale
    }
}

/// The interface size the player chooses, in steps of 5 %.
public enum InterfaceZoom {
    public static let range: ClosedRange<CGFloat> = 0.8...1.25
    public static let step: CGFloat = 0.05

    public static func clamped(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return min(range.upperBound, max(range.lowerBound, (value / step).rounded() * step))
    }

    public static func stepped(_ value: CGFloat, by steps: Int) -> CGFloat {
        clamped(clamped(value) + CGFloat(steps) * step)
    }
}
