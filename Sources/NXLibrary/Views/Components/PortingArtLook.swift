import SwiftUI
import NXLibraryCore
import ArcanePorting

/// A game's art while it ports (`PortingTileLook`): black and white, colour rising
/// from the bottom with the progress and a thin luminous line on its edge. Before
/// the shaders compile, a thin "k/n" bar with the stage and its step in small type
/// sits on the softly blurred art; then the percentage fades in, small, with a slow
/// pastel sheen. At rest, a game one gesture from playing keeps its colours, one that needs more is
/// softened, and one found nowhere is black and white; the corner mark says what to do. A Steam game still installing is
/// black and white, lightly blurred, with "Downloading" under a thin download mark that pulses (`PortingDownloadMark`).
///
/// The art is drawn once: a grey layer in `.saturation` blend takes the colour out
/// above the fill edge, feathered only for cloud transfers. The build sheen moves
/// only while compiling, and stands still with Reduce motion.
struct PortingArtLook: ViewModifier {
    let look: PortingTileLook
    let cornerRadius: CGFloat

    @Environment(\.seleneReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ZStack(alignment: .top) {
                    content
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: side * blur, opaque: true)
                    if case .transfer = look {
                        transferShade(height: geo.size.height, side: side)
                            .blendMode(.saturation)
                    } else {
                        Rectangle()
                            .fill(Color(hex: SeleneTokens.Art.grey))
                            .frame(height: geo.size.height * (1 - fill))
                            .blendMode(.saturation)
                    }
                }
                .compositingGroup()
                .saturation(isSoftened ? 0.35 : 1)
                .overlay(SeleneTheme.artShade.opacity(look == .missing ? 0.45 : isSoftened ? 0.28 : 0))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                if case .filling = look, fill > 0, fill < 1 {
                    edge(width: geo.size.width, side: side)
                        .offset(y: geo.size.height * (0.5 - fill))
                }
                overlay(side: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(fillAnimation, value: fill)
        .animation(Motion.buildArt(reduceMotion, .stage), value: stage)
    }

    // MARK: - Look

    private var fillAnimation: Animation? {
        if case .transfer = look { return Motion.transfer(reduceMotion) }
        return Motion.buildArt(reduceMotion, .fill)
    }

    private var fill: Double {
        switch look {
        case .normal, .engineUpdate, .toDownload, .toBuild, .toDownloadFiles, .unchecked: return 1
        case .preparing, .missing, .downloading: return 0
        case .filling(let value), .transfer(let value): return min(max(value, 0), 1)
        }
    }

    private var isSoftened: Bool { look == .toDownloadFiles || look == .unchecked }

    /// Blur as a fraction of the side.
    private var blur: CGFloat {
        switch look {
        case .preparing: return 0.02
        case .downloading: return 0.012
        default: return 0
        }
    }

    /// What sits on the art; animating between them is the slow dissolve.
    private enum Stage: Equatable { case none, steps, percent, download }

    private var stage: Stage {
        switch look {
        case .normal, .engineUpdate, .transfer, .toDownload, .toBuild, .toDownloadFiles, .unchecked, .missing: return .none
        case .preparing: return .steps
        case .filling: return .percent
        case .downloading: return .download
        }
    }

    /// Only the percentage's sheen moves.
    private var moving: Bool {
        guard !reduceMotion, case .filling = look else { return false }
        return true
    }

    private func transferShade(height: CGFloat, side: CGFloat) -> some View {
        let grey = Color(hex: SeleneTokens.Art.grey)
        let feather = side * 0.12
        // Keep exact grey and colour at the endpoints without snapping the gradient off.
        let half = feather / 2
        let correction = half * (max(0, 1 - 20 * fill) - max(0, 1 - 20 * (1 - fill)))
        return VStack(spacing: 0) {
            grey.frame(height: height)
            LinearGradient(stops: [
                .init(color: grey, location: 0),
                .init(color: grey.opacity(SeleneTokens.Alpha.heavy), location: 0.25),
                .init(color: grey.opacity(SeleneTokens.Alpha.half), location: 0.50),
                .init(color: grey.opacity(SeleneTokens.Alpha.soft), location: 0.75),
                .init(color: grey.opacity(0), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: feather)
        }
        .compositingGroup()
        .offset(y: -fill * height - half + correction)
        .frame(height: height, alignment: .top)
    }

    private func edge(width: CGFloat, side: CGFloat) -> some View {
        Rectangle()
            .fill(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.heavy))
            .frame(width: width, height: max(1, side * 0.008))
            .oortArtShadow(side * 0.025, strength: SeleneTokens.Alpha.strong, color: SeleneTheme.artInk)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func overlay(side: CGFloat) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !moving)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if stage == .steps, case .preparing(let step, let count, let title, let detail) = look {
                    steps(step: step, count: count, title: title, detail: detail, side: side)
                        .transition(.opacity)
                }
                if stage == .percent, case .filling(let value) = look {
                    percent(value, side: side, phase: moving ? time.truncatingRemainder(dividingBy: 9) / 9 : 0.35)
                        .transition(.opacity)
                }
                if stage == .download {
                    downloading(side: side)
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Before the shaders compile: "k/n" over a thin bar, then the stage and its step
    /// in very small type, on a soft shade so the white reads on any art.
    private func steps(step: Int, count: Int, title: String, detail: String, side: CGFloat) -> some View {
        let width = side * 0.62
        let fraction = count > 0 ? min(max(Double(step) / Double(count), 0), 1) : 0
        return ZStack {
            SeleneTheme.artShade.opacity(SeleneTokens.Alpha.mist)
            VStack(spacing: side * 0.035) {
                Text(count > 0 ? "\(step)/\(count)" : "…")
                    .font(.system(size: side * 0.085, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.near))
                ZStack(alignment: .leading) {
                    Capsule().fill(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.line))
                    Capsule().fill(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.heavy))
                        .frame(width: width * fraction)
                }
                .frame(width: width, height: max(1.5, side * 0.014))
                .animation(Motion.buildArt(reduceMotion, .steps), value: fraction)
                VStack(spacing: side * 0.008) {
                    Text(title)
                        .font(.system(size: side * 0.06, weight: .medium))
                        .foregroundColor(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.heavy))
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: side * 0.05))
                            .foregroundColor(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.muted))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: side * 0.84)
                .animation(Motion.buildArt(reduceMotion, .label), value: title)
            }
            .oortArtShadow(side * 0.02, strength: SeleneTokens.Alpha.half)
        }
    }

    /// Steam is still installing the game: the word in small type under the mark, which the tile draws outside its
    /// flattened picture (`PortingDownloadMark`) so it can pulse.
    private func downloading(side: CGFloat) -> some View {
        ZStack {
            // A soft shade, as under the porting steps, so the white reads on light art too.
            SeleneTheme.artShade.opacity(SeleneTokens.Alpha.mist)
            downloadMark(side: side)
        }
    }

    /// The download mark and its word, as fractions of the side, centred together on the tile: the circle (its
    /// symbol's point size; the drawn ring is about as wide) sits this far above the centre, the word's middle this
    /// far below, a small gap between them.
    static let downloadMarkSize: CGFloat = 0.18
    static let downloadMarkLift: CGFloat = 0.055
    static let downloadWordDrop: CGFloat = 0.1

    private func downloadMark(side: CGFloat) -> some View {
        Text(L10n.text("Downloading"))
            .font(.system(size: side * 0.06, weight: .medium))
            .foregroundColor(SeleneTheme.artInk.opacity(SeleneTokens.Alpha.heavy))
            .lineLimit(1)
            .frame(width: side * 0.84)
            .oortArtShadow(side * 0.04)
            .offset(y: side * Self.downloadWordDrop)
    }

    /// Soft pastels, never vivid; the blue kept faint: pink, peach, butter, mint, mist, lavender.
    private static let pastels: [Color] = [SeleneTokens.Art.pastel1, SeleneTokens.Art.pastel2, SeleneTokens.Art.pastel3, SeleneTokens.Art.pastel4, SeleneTokens.Art.pastel5, SeleneTokens.Art.pastel6]
        .map { Color(hex: $0) }

    /// The percentage, small and centred: solid white with a faint pastel sheen
    /// drifting slowly across it.
    private func percent(_ value: Double, side: CGFloat, phase: Double) -> some View {
        let text = Text("\(Int((value * 100).rounded(.down)))%")
            .font(.system(size: side * 0.115, weight: .semibold, design: .rounded))
            .monospacedDigit()
        let stops = [SeleneTheme.artInk] + Self.pastels + [SeleneTheme.artInk]
        let shift = CGFloat(phase) * 3 - 1.5
        return text
            .foregroundColor(SeleneTheme.artInk)
            .overlay(
                LinearGradient(colors: stops,
                               startPoint: UnitPoint(x: -0.5 + shift, y: 0.3),
                               endPoint: UnitPoint(x: 1.5 + shift, y: 0.7))
                    .mask(text)
                    .opacity(SeleneTokens.Alpha.veil)
            )
            .padding(.horizontal, side * 0.05)
            .padding(.vertical, side * 0.02)
            .background(Capsule().fill(SeleneTheme.artShade.opacity(SeleneTokens.Alpha.mist)))
            .oortArtShadow(side * 0.03, strength: SeleneTokens.Alpha.shade)
    }
}

extension View {
    func portingLook(_ look: PortingTileLook, cornerRadius: CGFloat) -> some View {
        modifier(PortingArtLook(look: look, cornerRadius: cornerRadius))
    }
}

/// A downloading game's mark, pulsing in brightness over the word "Downloading". A Core Animation view cannot be
/// drawn inside a tile flattened with `drawingGroup` (SwiftUI shows a placeholder instead), so the tile places
/// this over its face, outside the flattened picture, as it does its shine. Nothing for any other look.
struct PortingDownloadMark: View {
    let look: PortingTileLook
    let width: CGFloat
    let height: CGFloat

    @Environment(\.seleneReduceMotion) private var reduceMotion

    var body: some View {
        if look == .downloading {
            let side = min(width, height)
            DownloadMarkLayers(size: side * PortingArtLook.downloadMarkSize, still: reduceMotion)
                .frame(width: side * 0.3, height: side * 0.3)
                .offset(y: -side * PortingArtLook.downloadMarkLift)
                .frame(width: width, height: height)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}
