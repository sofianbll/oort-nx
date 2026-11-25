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
            HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.medium)) {
                picture
                VStack(alignment: .leading, spacing: canvas.u(SeleneTokens.Space.seam)) {
                    Text(verbatim: name)
                        .seleneFont(.text, .semibold)
                        .foregroundStyle(SeleneTheme.ink)
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
                Image(systemName: "arrow.up.right")
                    .seleneFont(.badge, .semibold)
                    .foregroundStyle(SeleneTheme.ink60)
                    .accessibilityHidden(true)
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

/// One category of credits: its title, then its cards two by two. `focusedCard` is the card under the controller.
struct OortCreditGroup: View {
    static let columns = 2

    @Environment(\.seleneCanvas) private var canvas
    @Environment(\.nxAppLocale) private var locale
    let group: Credits.Group
    let credits: Credits
    var focusedCard: String? = nil
    let open: (Credits.Credit) -> Void

    var body: some View {
        VStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            ForEach(Self.lines(group)) { line in
                HStack(alignment: .top, spacing: canvas.u(SeleneTokens.Space.small)) {
                    ForEach(line.credits) { credit in card(credit) }
                    // A last card alone keeps its column.
                    ForEach(line.credits.count..<Self.columns, id: \.self) { _ in Spacer(minLength: 0).frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .id("selene-row-\(line.id)")
            }
        }
    }

    private func card(_ credit: Credits.Credit) -> some View {
        let language = locale.language.rawValue
        return OortCreditCard(mark: Self.mark(credit, in: group.category), name: credit.name,
                              byline: credits.byline(of: credit, in: language), role: credits.role(of: credit, in: language),
                              hint: credits.label("opens", in: language), focused: focusedCard == credit.id) { open(credit) }
            .frame(maxWidth: .infinity)
    }

    /// One line of cards is one stop for the controller; left and right move inside it.
    struct Line: Identifiable {
        let id: String
        let credits: [Credits.Credit]
    }

    static func lines(_ group: Credits.Group) -> [Line] {
        stride(from: 0, to: group.credits.count, by: columns).map { start in
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
