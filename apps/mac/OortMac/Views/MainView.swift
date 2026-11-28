import SwiftUI
import OortLibrary

struct MainView: View {
    private let state: AppShellState

    @MainActor init(state: AppShellState) {
        self.state = state
    }

    var body: some View { AppShellView(state: state) }
}
