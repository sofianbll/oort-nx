import AppKit
import NXLibraryCore
import SwiftUI

struct DowngradeWarningView: View {
    let continueStartup: () -> Void
    private let context = AppLocale(language: .automatic, region: nil)

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.text("Before updating your library", context: context))
                .font(.system(size: 28, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(L10n.text("A verified copy of your launcher data is ready. Oort NX 0.3.0 cannot read new play history, can discard settings, and cannot resume pending cloud moves.", context: context))
                .font(.system(size: 17))
            Text(L10n.text("Before going back, finish cloud operations, quit both versions and keep a separate copy of your current launcher data. Do not use both versions on the same library.", context: context))
                .font(.system(size: 15))
            HStack(spacing: 24) {
                Button(L10n.text("Continue", context: context), action: continueStartup)
                    .keyboardShortcut(.defaultAction)
                Button(L10n.text("Open library folder", context: context)) { NSWorkspace.shared.open(AppData.supportRoot) }
                    .keyboardShortcut("o", modifiers: [.command])
                Button(L10n.text("Close", context: context)) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 620)
        .foregroundColor(.white)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.08, green: 0.09, blue: 0.12))
        .onAppear { LaunchReveal.show() }
    }
}
