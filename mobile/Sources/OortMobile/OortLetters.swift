import SwiftUI

/// Letters a controller can reach, to search the games: the system's keyboard cannot be driven with one.
struct OortLetters: View {
    enum Key: Hashable { case letter(Character), space, delete, done }
    static let rows: [[Key]] = ["ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ01", "2345678"].map { $0.map(Key.letter) }
        + [[.letter("9"), .space, .delete, .done]]

    let text: String
    let focused: Key?
    let press: (Key) -> Void

    var body: some View {
        VStack(spacing: SeleneTokens.Space.tight) {
            Text(text.isEmpty ? Oort.text("Search your games") : text)
                .font(.headline).foregroundStyle(text.isEmpty ? Oort.ink2 : Oort.ink).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            ForEach(Self.rows, id: \.self) { row in
                HStack(spacing: SeleneTokens.Space.tight) {
                    ForEach(row, id: \.self) { key in
                        Button { press(key) } label: { label(key).frame(maxWidth: .infinity, minHeight: 36) }
                            .buttonStyle(.plain)
                            .background { Color.clear.oortPanel(radius: Oort.key, focused: focused == key) }
                            .accessibilityAddTraits(focused == key ? .isSelected : [])
                    }
                }
            }
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(Oort.ink)
        // Six rows stay on the screen with the games above them.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .padding(SeleneTokens.Space.medium)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Oort.night.opacity(0.94))
    }

    @ViewBuilder private func label(_ key: Key) -> some View {
        switch key {
        case .letter(let letter): Text(String(letter))
        case .space: Image(systemName: "space").accessibilityLabel(Oort.text("Space"))
        case .delete: Image(systemName: "delete.left").accessibilityLabel(Oort.text("Erase"))
        case .done: Text(Oort.text("Done"))
        }
    }
}
