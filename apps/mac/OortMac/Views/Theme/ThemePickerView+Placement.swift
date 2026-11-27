import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NXLibraryCore

/// Placement: asking how a chosen wallpaper fills the screen and applying the answer.
extension ThemePickerView {
    // MARK: - Placement

    /// A chosen background; `id` nil is the theme's own.
    struct PendingWallpaper: Equatable {
        let id: String?
    }

    func askPlacement(_ id: String?) {
        placementFocus = .everywhere
        placing = PendingWallpaper(id: id)
        SoundEffectService.shared.play(.click)
    }

    func handlePlacement(_ action: GamepadAction) {
        switch action {
        case .navigateLeft, .navigateRight:
            let next = ActionBarOrder.move(placementFocus, by: action == .navigateLeft ? -1 : 1, in: placementAnswers.map(\.id))
            if next != placementFocus { placementFocus = next; SoundEffectService.shared.play(.focus) }
        case .confirm:
            place(placementFocus)
        case .cancel:
            place(.notNow)
        default: break
        }
    }

    private var placementAnswers: [DialogAnswer<WallpaperPlacement>] {
        ActionBarOrder.sorted(WallpaperPlacement.allCases.map { answer in
            DialogAnswer(answer, answer.title, answer == .notNow ? .back : answer == .everywhere ? .primary : .secondary)
        }, role: \.role)
    }

    /// Everywhere and Settings only apply it and close the menu; Not now keeps the gallery open, nothing changed.
    private func place(_ placement: WallpaperPlacement) {
        guard let pending = placing else { return }
        placing = nil
        placement.apply(pending.id, to: &settings.settings)
        if placement == .notNow {
            SoundEffectService.shared.play(.focus)
            return
        }
        SoundEffectService.shared.play(.click)
        router.closeMenu()
    }

    func placementDialog(_ pending: PendingWallpaper) -> some View {
        let name = pending.id == WallpaperCatalog.none ? L10n.text("No wallpaper")
            : pending.id.flatMap { theme.credits[$0]?.title } ?? theme.wallpaperTitle(for: pending.id)
        return ZStack {
            SeleneTheme.scrim45
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { place(.notNow) }
            SeleneChoiceDialog(title: WallpaperPlacement.dialogTitle,
                               message: L10n.format("%@. You can change both wallpapers any time in Settings → Look.", [String(describing: name)]),
                               answers: placementAnswers, focus: $placementFocus,
                               onCancel: { place(.notNow) }, onAnswer: place)
        }
    }
}
