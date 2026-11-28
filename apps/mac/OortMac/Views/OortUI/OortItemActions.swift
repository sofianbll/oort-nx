import SwiftUI
import OortLibrary

/// What the hints offer besides A and B, drawn on the screen too: hints can be hidden, these keys stay for the mouse.
/// The same items feed both, so a name never differs. What deletes is last, apart.
struct OortItemActions: View {
    @Environment(\.seleneCanvas) private var canvas
    let hints: [HintItem]
    var deletes: Set<PromptButton> = []

    static func offered(_ hints: [HintItem]) -> [HintItem] {
        hints.filter { $0.action != nil && $0.button != .a && $0.button != .b && $0.button != .lb && $0.button != .rb }
    }

    var body: some View {
        let items = Self.offered(hints)
        let erase = { (item: HintItem) in item.button.map(deletes.contains) == true }
        HStack(spacing: canvas.u(SeleneTokens.Space.small)) {
            ForEach(items.filter { !erase($0) }) { key($0, tone: .normal) }
            ForEach(items.filter(erase)) { item in
                key(item, tone: .destructive).padding(.leading, items.count > 1 ? canvas.u(SeleneTokens.Space.group) : 0)
            }
        }
    }

    private func key(_ item: HintItem, tone: OortButton.Tone) -> some View {
        OortButton(title: item.label, preset: .compact, tone: tone) { item.action?() }
    }
}

extension View {
    /// The same actions on a right click.
    func oortItemMenu(_ hints: [HintItem], deletes: Set<PromptButton> = []) -> some View {
        contextMenu {
            ForEach(OortItemActions.offered(hints)) { item in
                Button(L10n.text(item.label), role: item.button.map(deletes.contains) == true ? .destructive : nil) { item.action?() }
            }
        }
    }
}
