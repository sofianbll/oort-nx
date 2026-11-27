import SwiftUI
import NXLibraryCore

private struct SeleneCanvasKey: EnvironmentKey {
    static let defaultValue = SeleneCanvas(size: SeleneCanvas.design)
}

private struct SeleneMinimumFontKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var seleneMinimumFont: CGFloat {
        get { self[SeleneMinimumFontKey.self] }
        set { self[SeleneMinimumFontKey.self] = newValue }
    }
    var seleneCanvas: SeleneCanvas {
        get { self[SeleneCanvasKey.self] }
        set { self[SeleneCanvasKey.self] = newValue }
    }
}

private struct SeleneFontModifier: ViewModifier {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneMinimumFont) private var minimum
    @Environment(\.dynamicTypeSize) private var dynamicType
    let size: CGFloat
    let weight: Font.Weight
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        // The default is the reference canvas. Accessibility text size is not
        // shrunk with narrow windows; actual glyph height must be measured.
        let scale: CGFloat = switch dynamicType {
        case .accessibility1: 1.25
        case .accessibility2: 1.5
        case .accessibility3: 1.75
        case .accessibility4, .accessibility5: 2
        default: 1
        }
        let base = scale == 1 ? canvas.u(size) : size * scale
        return content.font(.system(size: max(minimum, base), weight: weight, design: design))
    }
}

private struct SeleneCanvasRoot: ViewModifier {
    let zoom: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.seleneCanvas, SeleneCanvas(size: proxy.size, zoom: zoom))
        }
        // Full bleed under the hidden title bar: windowed looks like full screen.
        .ignoresSafeArea()
    }
}

extension View {
    /// System font sized in Selene canvas units.
    func seleneFont(_ size: CGFloat, _ weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(SeleneFontModifier(size: size, weight: weight, design: design))
    }

    func seleneFont(_ token: SeleneTokens.Text, _ weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        seleneFont(token.rawValue, weight, design: design)
    }

    /// Fades a scrolling row out over `fraction` of its width on each requested side.
    func horizontalEdgeFade(_ fraction: CGFloat = 0.15, edges: Edge.Set = .horizontal) -> some View {
        mask(LinearGradient(stops: [.init(color: edges.contains(.leading) ? .clear : .black, location: 0),
                                    .init(color: .black, location: fraction),
                                    .init(color: .black, location: 1 - fraction),
                                    .init(color: edges.contains(.trailing) ? .clear : .black, location: 1)],
                            startPoint: .leading, endPoint: .trailing))
    }

    /// Measures the available space and publishes it as `seleneCanvas`.
    func seleneCanvasRoot(zoom: CGFloat = 1) -> some View {
        modifier(SeleneCanvasRoot(zoom: zoom))
    }
}
