import AppKit
import OortCore
import SwiftUI
import NXLibraryCore

/// A project Oort NX owes something to: its mark, its name, who makes it under which licence, and what it does here.
struct OortCreditCard: View {
    enum Mark {
        case art(NSImage), platform(PlatformKind), glyph(MaterialIcon)
    }

    @Environment(\.seleneCanvas) private var canvas
    let mark: Mark
    let name: String
    let byline: String
    var role: String? = nil
    var hint: String? = nil
    var focused = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.small)) {
                picture
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                    // The arrow stands beside the name; the rest has the whole width.
                    HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.tight)) {
                        Text(verbatim: name)
                            .seleneFont(.text, .semibold)
                            .foregroundStyle(SeleneTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .seleneFont(.badge, .semibold)
                            .foregroundStyle(SeleneTheme.ink60)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: byline)
                        .seleneFont(.badge)
                        .foregroundStyle(SeleneTheme.ink75)
                    if let role {
                        Text(verbatim: role)
                            .seleneFont(.badge)
                            .foregroundStyle(SeleneTheme.ink90)
                            .padding(.top, canvas.u(SeleneTokens.Space.hairline))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .multilineTextAlignment(.leading)
            .padding(canvas.u(SeleneTokens.Space.medium))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .oortPanel(radius: radius, raised: focused)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(OortPressStyle())
        .oortPadPress(focused)
        .seleneRowFocus(focused, radius: radius)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, byline, role ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(.isLink)
    }

    private var radius: CGFloat { canvas.u(SeleneTokens.Radius.card) }

    private var picture: some View {
        let side = canvas.u(SeleneTokens.Space.group)
        return ZStack {
            if case .art = mark {} else {
                RoundedRectangle(cornerRadius: canvas.u(SeleneTokens.Radius.content), style: .continuous).fill(SeleneTheme.ink15)
            }
            switch mark {
            case .art(let image): Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            case .platform(let kind): PlatformMark(kind: kind)
            case .glyph(let icon): MaterialIconView(icon, size: SeleneTokens.Space.large)
            }
        }
        .foregroundStyle(SeleneTheme.ink)
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// Full columns of cards of one height, or a list where each has its own. The same rule as the site and the other apps: `Credits.columns`.
struct OortCreditGrid: Layout {
    let columns: Int
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = heights(subviews, in: width)
        return CGSize(width: width, height: heights.reduce(0, +) + CGFloat(max(heights.count - 1, 0)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = column(in: bounds.width)
        var y = bounds.minY
        for (line, height) in heights(subviews, in: bounds.width).enumerated() {
            for place in 0..<columns where line * columns + place < subviews.count {
                subviews[line * columns + place].place(at: CGPoint(x: bounds.minX + CGFloat(place) * (width + spacing), y: y),
                                                       proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }

    private func column(in width: CGFloat) -> CGFloat { max((width - CGFloat(columns - 1) * spacing) / CGFloat(columns), 0) }

    /// One height per line; the lines of a grid share theirs.
    private func heights(_ subviews: Subviews, in width: CGFloat) -> [CGFloat] {
        let cards = subviews.map { $0.sizeThatFits(ProposedViewSize(width: column(in: width), height: nil)).height }
        guard columns > 1 else { return cards }
        return Array(repeating: cards.max() ?? 0, count: (cards.count + columns - 1) / columns)
    }
}

/// One category of credits: the six cards as a full grid, the others as a list. `focusedCard` is the card under the controller.
struct OortCreditGroup: View {
    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let group: Credits.Group
    let credits: Credits
    /// How many columns the page has room for: `fitting(_:canvas:)`.
    let fitting: Int
    var focusedCard: String? = nil
    let open: (Credits.Credit) -> Void

    var body: some View {
        let lines = Self.lines(group, credits, fitting: fitting)
        OortCreditGrid(columns: credits.columns(for: group, fitting: fitting), spacing: canvas.u(SeleneTokens.Space.small)) {
            ForEach(group.credits) { credit in
                // The line's first card is where the page scrolls to.
                if let line = lines.first(where: { $0.credits[0].id == credit.id }) {
                    card(credit).id("selene-row-\(line.id)")
                } else {
                    card(credit)
                }
            }
        }
    }

    /// The columns that fit a page of this width.
    static func fitting(_ width: CGFloat, canvas: SeleneCanvas) -> Int {
        let gap = canvas.u(SeleneTokens.Space.small)
        return max(Int((width + gap) / (canvas.u(SeleneTokens.Space.creditCard) + gap)), 1)
    }

    private func card(_ credit: Credits.Credit) -> some View {
        let language = locale.language.rawValue
        return OortCreditCard(mark: Self.mark(credit, in: group.category), name: credit.name,
                              byline: credits.byline(of: credit, in: language), role: credits.role(of: credit, in: language),
                              hint: credits.label("opens", in: language), focused: focusedCard == credit.id) { open(credit) }
    }

    /// One line of cards is one stop for the controller; left and right move inside it.
    struct Line: Identifiable {
        let id: String
        let credits: [Credits.Credit]
    }

    static func lines(_ group: Credits.Group, _ credits: Credits, fitting: Int) -> [Line] {
        let columns = credits.columns(for: group, fitting: fitting)
        return stride(from: 0, to: group.credits.count, by: columns).map { start in
            let row = Array(group.credits[start..<min(start + columns, group.credits.count)])
            return Line(id: "credit-" + row[0].id, credits: row)
        }
    }

    private static func mark(_ credit: Credits.Credit, in category: Credits.Category) -> OortCreditCard.Mark {
        let glyph = glyph(credit.glyph ?? category.glyph)
        guard let picture = credit.picture else { return .glyph(glyph) }
        if let kind = PlatformKind(rawValue: picture) { return .platform(kind) }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Brands/Credits/\(picture).png"),
              let image = NSImage(contentsOf: url) else { return .glyph(glyph) }
        return .art(image)
    }

    static func glyph(_ name: String) -> MaterialIcon {
        switch name {
        case "heart": .favorite
        case "gamepad": .gamepad
        case "terminal": .terminal
        case "puzzle": .puzzle
        case "palette": .palette
        case "globe": .language
        default: .build
        }
    }
}
