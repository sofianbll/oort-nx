import SwiftUI
import OortLibrary

/// System → Console: the build and launch logs, to filter, search and copy.
struct SettingsConsoleSection: View {
    let onActions: ([SettingsRowAction]) -> Void
    let onOpenConsole: () -> Void

    var body: some View {
        OortSettingsGroup {
            SeleneButtonRow("Console",
                            subtitle: "Filter, search and copy build and launch logs.",
                            buttonTitle: "Open") {
                onOpenConsole()
            }
        }
        .onAppear {
            onActions([.init(id: "console", title: "Console") { onOpenConsole() }])
        }
    }
}
