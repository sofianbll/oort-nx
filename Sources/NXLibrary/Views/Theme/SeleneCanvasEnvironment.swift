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
    let size: CGFloat
    let weight: Font.Weight
    var design: Font.Design = .default

    func body(content: Content) -> some View {
        content.font(.system(size: max(minimum, canvas.u(size)), weight: weight, design: design))
    }
}

private struct SeleneCanvasRoot: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .environment(\.seleneCanvas, SeleneCanvas(size: proxy.size))
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
    func seleneCanvasRoot() -> some View {
        modifier(SeleneCanvasRoot())
    }
}
