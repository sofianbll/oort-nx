import SwiftUI
import NXLibraryCore
import ArcanePorting

struct SaveImportDetails: View {
    let source: URL
    let destination: URL
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView { content }
        }
        .multilineTextAlignment(.center)
        .padding(.top, canvas.u(SeleneTokens.Space.large))
    }

    private var content: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.medium)) {
            VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
                endpoint(L10n.text("From"), folder: source)
                SaveTransferArrow()
                endpoint("To", folder: destination)
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
            .padding(.vertical, canvas.u(SeleneTokens.Space.small))
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.badge), style: .continuous)
                .fill(SeleneTheme.glassLight))

            VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
                Text(L10n.text("Your current save is backed up before replacement."))
                    .seleneFont(.text, .medium)
                    .foregroundColor(SeleneTheme.ink)
                Text(SavePresentation.importWarning)
                    .seleneFont(.text)
                    .foregroundColor(SeleneTheme.ink60)
                    .lineSpacing(canvas.u(3))
            }
            .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func endpoint(_ label: String, folder: URL) -> some View {
        let path = (folder.path as NSString).abbreviatingWithTildeInPath
        return VStack(spacing: canvas.u(SeleneTokens.Space.compact)) {
            Text(verbatim: label.uppercased())
                .seleneFont(.badge, .semibold)
                .tracking(canvas.u(1.2))
                .foregroundColor(SeleneTheme.ink60)
            // Give long directory names a natural wrap point after each slash.
            Text(verbatim: path.replacingOccurrences(of: "/", with: "/\u{200B}"))
                .seleneFont(.text)
                .lineSpacing(canvas.u(2))
                .foregroundColor(SeleneTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, canvas.u(SeleneTokens.Space.small))
                .padding(.vertical, canvas.u(SeleneTokens.Space.small))
                .frame(maxWidth: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.row), style: .continuous)
                        .strokeBorder(SeleneTheme.ink15, lineWidth: SeleneTokens.Space.thinStroke / displayScale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .help(folder.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(folder.path)
    }
}

private struct SaveTransferArrow: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.seleneReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.controlActiveState) private var windowState
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion || systemReduceMotion || windowState == .inactive {
                glyph.foregroundStyle(SeleneTheme.ink60)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { tick in
                    litGlyph(at: tick.date.timeIntervalSince(start))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var glyph: some View {
        Image(systemName: "arrow.down")
            .seleneFont(.row, .light)
            .scaleEffect(x: 1, y: 1.22)
            .frame(height: canvas.u(28))
    }

    private func litGlyph(at elapsed: TimeInterval) -> some View {
        let centre = TileMotion.shineCentre(at: elapsed)
        let radius = TileMotion.shineHalfWidth
        return glyph.foregroundStyle(LinearGradient(
            colors: [SeleneTheme.ink60, SeleneTheme.ink.opacity(SeleneTokens.Alpha.heavy), SeleneTheme.ink60],
            startPoint: UnitPoint(x: 0.5, y: centre - radius),
            endPoint: UnitPoint(x: 0.5, y: centre + radius)))
    }
}
