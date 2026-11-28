import SwiftUI
import OortLibrary

// What the Selene pieces draw, said by the pieces themselves while a probe reads it (ScreenView's parity).
/// One piece as it was drawn, for the parity check against a reference tree (OortCore ScreenTree).
struct ScreenTracePiece: Equatable {
    enum Kind: String { case row, dot, `switch`, pill, hint, text, question }
    let kind: Kind
    var text: String? = nil
    var about: String? = nil
    var tone: Screen.Tone? = nil
    var on: Bool? = nil
    var focused: Bool? = nil
    var destructive: Bool? = nil
    /// A hint's key and side of the bar.
    var key: String? = nil
    var left: Bool? = nil
    /// A text's typographic role.
    var role: ScreenTree.Words.Role? = nil
}

struct ScreenTraceKey: PreferenceKey {
    static let defaultValue: [ScreenTracePiece] = []
    static func reduce(value: inout [ScreenTracePiece], nextValue: () -> [ScreenTracePiece]) { value += nextValue() }
}

extension EnvironmentValues {
    /// On while a probe reads what the pieces draw; off everywhere else.
    @Entry var screenTrace = false
}

extension View {
    /// The piece first, then what it holds.
    func screenTrace(_ on: Bool, _ pieces: @autoclosure () -> [ScreenTracePiece]) -> some View {
        let drawn = on ? pieces() : []
        return transformPreference(ScreenTraceKey.self) { $0.insert(contentsOf: drawn, at: 0) }
    }
}
