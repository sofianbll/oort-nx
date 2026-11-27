import AppKit
import NXLibraryCore

/// A page in the browser. From a controller it asks first: nothing there brings the player back to Oort.
@MainActor func openWebPage(_ url: URL, viewModel: AppViewModel) {
    guard GameControllerService.shared.controllerInHand else { NSWorkspace.shared.open(url); return }
    viewModel.confirmSetting(L10n.text("Open this page in the browser?"), message: url.absoluteString, action: "Open page") {
        NSWorkspace.shared.open(url)
    }
}
