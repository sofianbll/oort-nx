import SwiftUI
import NXLibraryCore
import ArcanePorting

/// The rows of each Add game step. The first rows are the step's next move (as
/// Play leads Game options); details and settings follow under small headings.
extension AddGameView {
    func rows(for step: Int) -> [AddGameRow] {
        switch step {
        case 1: return chooseRows
        case 2: return reviewRows
        default: return portingRows
        }
    }

    /// The row a step opens on.
    func defaultRowID(for step: Int) -> String {
        switch step {
        case 1, 2 where keysBlock: return "keys"
        case 1: return porting.canAddSelectedGame ? "continue" : "chooseFiles"
        case 2: return porting.canStartBuild ? "build" : "library"
        default: return portingRows.first(where: \.focusable)?.id ?? ""
        }
    }

    // MARK: - Choose

    private var chooseRows: [AddGameRow] {
        var rows: [AddGameRow] = []
        let folder = porting.selectedGameFolder
        rows.append(AddGameRow(id: "chooseFiles", kind: .action { porting.selectGameFiles() },
                               icon: .add, title: L10n.text("Choose game files"),
                               about: ryujinx ? L10n.text("NSP, XCI, PFS0, NCA or NRO.") : L10n.text("NSP, XCI, NSZ, XCZ or a Switch 2 NUP.")))
        if !ryujinx {
            let adoptionBlocker = viewModel.localAppAdoptionBlocker
            rows.append(AddGameRow(id: "adoptApp", kind: .action { viewModel.chooseLocalApp() },
                                   icon: .add, title: L10n.text("Add ported app"),
                                   about: adoptionBlocker ?? L10n.text("Copy a local nxnative app into Game apps."),
                                   enabled: adoptionBlocker == nil))
        }
        rows.append(AddGameRow(id: "choose", kind: .action { porting.selectGameFolder() },
                               icon: .folder, title: folder == nil ? L10n.text("Choose folder") : L10n.text("Change folder"),
                               about: folder.map { ($0.path as NSString).abbreviatingWithTildeInPath }
                                   ?? L10n.text("Game packages or an extracted game folder. You can also drop them here.")))
        if let game = porting.selectedGame {
            rows.append(AddGameRow(id: "continue", kind: .action(goToReview), icon: .chevron,
                                   title: L10n.text("Continue"),
                                   about: "\(game.name) · \(selectionSummary) · \(porting.formattedSelectedSourcesSize)",
                                   enabled: porting.canAddSelectedGame))
        }
        // Keys that stop the game come right after the next move, not under the sources.
        let blocking = readinessRows(includeBuildError: false)
        if keysBlock { rows += blocking }
        if porting.isScanningGameFolder {
            rows.append(AddGameRow(id: "scanning", kind: .note, title: L10n.text("Reading the folder…")))
        }
        if let error = porting.scanError {
            rows.append(AddGameRow(id: "scanError", kind: .warning(action: nil),
                                   title: porting.detectedGames.isEmpty ? L10n.text("Could not read this folder") : L10n.text("Some files were skipped"), about: error))
        }
        if let error = viewModel.dropErrorMessage {
            rows.append(AddGameRow(id: "dropError", kind: .warning(action: nil), title: error))
        }
        if folder != nil, !porting.isScanningGameFolder, porting.detectedGames.isEmpty, porting.scanError == nil {
            rows.append(AddGameRow(id: "empty", kind: .note, title: L10n.text("No games were found in this folder.")))
        }
        if porting.detectedGames.count > 1 {
            rows.append(AddGameRow(id: "gamesHeading", kind: .heading, title: L10n.text("Choose a game")))
            for game in porting.detectedGames {
                rows.append(AddGameRow(id: "game:\(game.id)", kind: .action { porting.selectedGame = game },
                                       title: game.name, about: "\(game.summaryText) · \(game.titleId ?? game.id)", compact: true,
                                       checked: porting.selectedGame?.id == game.id))
            }
        }
        if let game = porting.selectedGame {
            rows.append(AddGameRow(id: "sourcesHeading", kind: .heading, title: L10n.text("Sources")))
            if !game.hasGame {
                rows.append(AddGameRow(id: "noBase", kind: .warning(action: nil),
                                       title: ryujinx ? L10n.text("This update needs its base game") : L10n.text("Base game required"),
                                       about: ryujinx ? L10n.text("Ryujinx starts a game from its base game. Add the base game’s file with this update.")
                                           : L10n.text("This folder has an update or DLC but no base game.")))
            } else if game.isUpdateOnly {
                // The engine's NO_BASE note (nxnative 777a5f6c): nothing in the file proves the update is complete.
                let folder = game.files.contains { $0.layout == .extracted }
                rows.append(AddGameRow(id: "updateOnlyNUP", kind: .warning(action: nil),
                                       title: folder ? L10n.text("No base game in this folder") : L10n.text("No base game in this NUP"),
                                       about: folder ? L10n.text("The selected update is played as the whole game. If the game stops on missing files, add the base game’s dump (base/exefs and base/romfs).")
                                           : L10n.text("The selected update is played as the whole game. If the game stops on missing files, use a NUP that includes the base game.")))
            }
            // The same note for an NSP, a NUP or a folder: the engine makes a provisional profile for each.
            if !ryujinx, !viewModel.setup.hasVerifiedEngineProfile(titleId: game.titleId) {
                rows.append(AddGameRow(id: "noProfile", kind: .warning(action: nil), title: L10n.text("Not tested with this engine yet"),
                                       about: L10n.text("The engine has no profile for this game, so it makes a provisional one. ")
                                           + L10n.text("The porting may stop, or the game may not start.")))
            }
            for item in game.files {
                let locked = SourceSelection.isLocked(item, in: game.files, selected: porting.selectedSourceIDs)
                rows.append(AddGameRow(
                    id: "source:\(item.id)",
                    kind: .toggle(Binding(get: { porting.selectedSourceIDs.contains(item.id) },
                                          set: { on in
                                              if on != porting.selectedSourceIDs.contains(item.id) {
                                                  porting.toggleSource(item)
                                              }
                                          })),
                    title: item.name, about: sourceAbout(item), compact: true))
                if locked { rows[rows.count - 1].enabled = false }
            }
            rows.append(AddGameRow(id: "sourcesNote", kind: .note,
                                   title: game.isUpdateOnly || !game.files.contains(where: { $0.kind == .base })
                                       ? L10n.text("One update at a time; bundled DLC stay together.")
                                       : L10n.text("The base stays in. One update at a time; bundled DLC stay together.")))
        }
        if !keysBlock { rows += blocking }
        rows.append(ryujinx ? filesStayRow : destinationRow)
        return rows
    }

    /// Where the keys go, in words true on the Mac and the PC once the proposal is on.
    private var keysCopyNote: String {
        setup.readiness == nil ? L10n.text("Copied once to Application Support, readable only by you.")
            : L10n.text("Copied once to Oort’s private folder, readable only by you.")
    }

    /// Proposal (feat/proposition-accueil-ryujinx): the engine in use reads files without compiling them.
    private var ryujinx: Bool { setup.readiness?.engine == .ryujinx }

    /// Keys missing, or too old for the checked files: their fix comes before the step's other moves.
    var keysBlock: Bool {
        (porting.selectedSourcesRequireKeys && !setup.isProdKeysValid) || porting.keyCheckBlocks
    }

    /// What will be played, in words: "Game + update 2.0.2 + 1 DLC".
    var selectionSummary: String {
        let picked = porting.selectedSources
        var parts: [String] = []
        if picked.contains(where: { $0.kind == .base }) { parts.append(L10n.text("Game")) }
        if let update = picked.first(where: { $0.kind == .update }) {
            let raw = (update.versionString ?? "").trimmingCharacters(in: .whitespaces)
            let version = raw.lowercased().hasPrefix("v") ? String(raw.dropFirst()) : raw
            parts.append(version.isEmpty ? L10n.text("Update") : L10n.format("update %@", [version]))
        }
        let dlc = Set(picked.filter { $0.kind == .dlc }.map(\.id)).count
        if dlc > 0 { parts.append(L10n.format("%@ DLC", [String(dlc)])) }
        return parts.isEmpty ? sourceCountText : parts.joined(separator: " + ")
    }

    private var sourceCountText: String {
        let count = Set(porting.selectedSources.map { $0.url.resolvingSymlinksInPath().path }).count
        return L10n.count("%lld sources", count)
    }

    private func sourceAbout(_ item: GameFileItem) -> String {
        var parts = [item.type.title]
        if let raw = item.versionString?.trimmingCharacters(in: .whitespaces), !raw.isEmpty {
            parts.append(raw.lowercased().hasPrefix("v") ? raw : "v\(raw)")
        }
        let bundled = porting.selectedGame?.files.contains { $0.id != item.id && $0.url == item.url } == true
        if bundled && item.type != .base { parts.append(item.layout == .container ? L10n.text("In the NUP file") : L10n.text("In package")) }
        else { parts.append(item.layout == .extracted ? L10n.text("Extracted folder") : item.formattedSize) }
        return parts.joined(separator: " · ")
    }

    func goToReview() {
        guard porting.canAddSelectedGame else { return }
        withAnimation(reduceMotion ? nil : SeleneTheme.standard) { porting.goToWizardStep(2) }
    }

    // MARK: - Review

    private var reviewRows: [AddGameRow] {
        if ryujinx { return ryujinxReviewRows }
        var rows: [AddGameRow] = [
            AddGameRow(id: "build", kind: .action { addSelectedGame(buildNow: true) }, icon: .build,
                       title: porting.selectedLibraryGame == nil ? L10n.text("Add and port") : L10n.text("Rebuild"), about: buildHint, enabled: porting.canStartBuild),
            AddGameRow(id: "library", kind: .action { addSelectedGame(buildNow: false) }, icon: .add,
                       title: porting.selectedLibraryGame == nil ? L10n.text("Add to library only") : L10n.text("Save changes"),
                       about: porting.selectedLibraryGame == nil ? L10n.text("Port later") : L10n.text("Next launch"),
                       enabled: porting.canAddSelectedGame),
            AddGameRow(id: "sources", kind: .action {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) { porting.goToWizardStep(1) }
            }, icon: .folder, title: L10n.text("Change sources"),
               about: "\(selectionSummary) · \(porting.formattedSelectedSourcesSize)"),
            AddGameRow(id: "runtimeHeading", kind: .heading, title: L10n.text("Next launch")),
            toggle("fps60", "60 FPS", "Frame-rate target",
                   $porting.pendingRuntimeConfig.enable60FPS),
            toggle("docked", "Docked mode", "Console profile",
                   $porting.pendingRuntimeConfig.isDockedMode),
            toggle("metalFX", "MetalFX upscaling", "Sharper scaling of the whole picture to your screen",
                   $porting.pendingRuntimeConfig.enableMetalFXUpscale),
            toggle("metalHUD", "Metal HUD", "Performance overlay",
                   $porting.pendingRuntimeConfig.enableMetalHUD),
            AddGameRow(id: "appHeading", kind: .heading, title: L10n.text("App")),
        ]
        let languages = languageOptions
        let current = languages.firstIndex { $0.code == porting.pendingRuntimeConfig.language } ?? 0
        rows.append(AddGameRow(id: "language", kind: .choice(values: languages.map(\.label), index: current) { index in
            guard languages.indices.contains(index) else { return }
            porting.pendingRuntimeConfig.language = languages[index].code
        }, title: L10n.text("Game language"), compact: true))
        rows.append(AddGameRow(id: "appName", kind: .field($porting.appName, placeholder: porting.selectedGame?.name ?? L10n.text("Name")),
                               title: L10n.text("App name"), compact: true))
        if porting.selectedLibraryGame == nil {
            rows.append(AddGameRow(id: "bundleID", kind: .field($porting.bundleId, placeholder: "org.nxnative.game"),
                                   title: L10n.text("Bundle identifier"), compact: true))
        }
        let readiness = readinessRows(includeBuildError: true)
        rows = keysBlock ? readiness + rows : rows + readiness
        rows.append(destinationRow)
        return rows
    }

    /// Ryujinx-Nextendo reads the files where they are: no build, no app name. The checked update and DLC are what
    /// it will load; MetalFX and the Metal HUD belong to the Mac engine and are not offered.
    private var ryujinxReviewRows: [AddGameRow] {
        var rows: [AddGameRow] = [
            AddGameRow(id: "library", kind: .action { addSelectedGame(buildNow: false) }, icon: .add,
                       title: porting.selectedLibraryGame == nil ? L10n.text("Add to library") : L10n.text("Save changes"),
                       about: L10n.text("Ryujinx loads the update and DLC you checked."),
                       enabled: porting.canAddSelectedGame && !keysBlock),
            AddGameRow(id: "sources", kind: .action {
                withAnimation(reduceMotion ? nil : SeleneTheme.standard) { porting.goToWizardStep(1) }
            }, icon: .folder, title: L10n.text("Change sources"),
               about: "\(selectionSummary) · \(porting.formattedSelectedSourcesSize)"),
            AddGameRow(id: "runtimeHeading", kind: .heading, title: L10n.text("Next launch")),
            toggle("fps60", "60 FPS", "Frame-rate target", $porting.pendingRuntimeConfig.enable60FPS),
            toggle("docked", "Docked mode", "Console profile", $porting.pendingRuntimeConfig.isDockedMode),
        ]
        let languages = languageOptions
        let current = languages.firstIndex { $0.code == porting.pendingRuntimeConfig.language } ?? 0
        rows.append(AddGameRow(id: "language", kind: .choice(values: languages.map(\.label), index: current) { index in
            guard languages.indices.contains(index) else { return }
            porting.pendingRuntimeConfig.language = languages[index].code
        }, title: L10n.text("Game language"), compact: true))
        let readiness = readinessRows(includeBuildError: false)
        rows = keysBlock ? readiness + rows : rows + readiness
        rows.append(filesStayRow)
        return rows
    }

    private var filesStayRow: AddGameRow {
        AddGameRow(id: "destination", kind: .note, title: L10n.text("Your files stay where they are. Nothing is copied or converted."))
    }

    private func toggle(_ id: String, _ title: String, _ about: String, _ isOn: Binding<Bool>) -> AddGameRow {
        AddGameRow(id: id, kind: .toggle(isOn), title: L10n.text(title), about: L10n.text(about), compact: true)
    }

    private var buildHint: String {
        if viewModel.isCheckingCloudBuild { return L10n.text("Checking the cloud build cache…") }
        if porting.canStartBuild { return L10n.text("Builds the Mac app now; you can keep using the library meanwhile.") }
        if !porting.supportsSources(porting.selectedSources) { return L10n.text("These sources need a newer engine.") }
        if porting.selectedSourcesRequireKeys && !setup.isProdKeysValid { return L10n.text("Import prod.keys first.") }
        if porting.keyCheckBlocks, let readiness = porting.keyCheck?.readiness { return "\(readiness.title)." }
        if !setup.isNxnativeValid { return L10n.text("The nxnative checkout is missing.") }
        if setup.environmentStatus?.canBuild != true { return L10n.text("The build environment is incomplete.") }
        if !setup.canPassToolchainGate { return L10n.text("The toolchain is not certified; enable the override in Settings.") }
        return L10n.text("Not available yet.")
    }

    private var languageOptions: [(code: String, label: String)] {
        var options = viewModel.availableLanguages.map { (code: $0.code, label: L10n.text($0.label)) }
        let current = porting.pendingRuntimeConfig.language
        if !options.contains(where: { $0.code == current }) {
            options.append((current, current.isEmpty ? L10n.text("Game default") : current))
        }
        return options
    }

    private func addSelectedGame(buildNow: Bool) {
        porting.addSelectedGame(buildNow: buildNow)
        guard porting.buildError == nil, !viewModel.isBuilding, !viewModel.isCheckingCloudBuild else { return }
        router.showLibrary()
    }

    // MARK: - Readiness

    private func readinessRows(includeBuildError: Bool) -> [AddGameRow] {
        var rows: [AddGameRow] = []
        if includeBuildError, let error = porting.buildError {
            rows.append(AddGameRow(id: "buildError", kind: .warning(action: {
                porting.buildError = nil
                porting.portingFailureReason = nil
            }), title: porting.portingFailureReason?.title ?? L10n.text("The last porting failed"), about: error))
        }
        if porting.selectedSourcesRequireKeys && !setup.isProdKeysValid {
            rows.append(AddGameRow(id: "keys", kind: .action { setup.selectProdKeysFile() }, icon: .key,
                                   title: L10n.text("Import prod.keys"),
                                   about: keysCopyNote))
        }
        if setup.isProdKeysValid, let readiness = porting.keyCheck?.readiness {
            if readiness.warning {
                rows.append(AddGameRow(id: "keyCheck", kind: .warning(action: nil),
                                       title: readiness.title, about: readiness.about))
                rows.append(AddGameRow(id: "keys", kind: .action { setup.selectProdKeysFile() }, icon: .key,
                                       title: L10n.text("Import prod.keys"),
                                       about: keysCopyNote))
            } else {
                rows.append(AddGameRow(id: "keyCheck", kind: .note, title: "\(readiness.title). \(readiness.about)"))
            }
        }
        if let environment = setup.environmentStatus, environment.xcodeVersion == nil {
            rows.append(AddGameRow(id: "xcode", kind: .action { viewModel.reopenSetup() }, icon: .checklist,
                                   title: L10n.text("Open Setup"), about: L10n.text("Xcode is not ready; a porting needs it.")))
        }
        if porting.isDiskSpaceLow {
            rows.append(AddGameRow(id: "disk", kind: .warning(action: nil), title: L10n.text("Not enough disk space"),
                                   about: porting.diskSpaceWarningMessage))
        }
        return rows
    }

    private var destinationRow: AddGameRow {
        if let problem = porting.buildDestinationProblem {
            return AddGameRow(id: "destination", kind: .warning(action: nil), title: L10n.text("App folder unavailable"), about: problem)
        }
        return AddGameRow(id: "destination", kind: .note,
                          title: L10n.format("Installs to %@. On a failure or a cancel the previous app stays as it was.", [String(describing: porting.selectedBuildAppURL.path)]))
    }

    // MARK: - Porting

    /// The porting step's actions (published by `AddGameStepThreeView`) as rows; its log has its own toggle.
    private var portingRows: [AddGameRow] {
        guard actionsStep == 3 else { return [] }
        return actions.filter { $0.id != "log" }.map { action in
            AddGameRow(id: action.id, kind: .action(action.perform), icon: Self.portingIcons[action.id] ?? .chevron,
                       title: action.title, enabled: action.isEnabled, destructive: action.id == "cancel")
        }
    }

    private static let portingIcons: [String: MaterialIcon] = [
        "cancel": .close, "openLog": .history, "console": .terminal, "play": .play,
        "library": .collections, "another": .add, "reveal": .folder, "retry": .restartAlt,
        "options": .tune, "review": .chevronLeft, "portAnyway": .restartAlt, "engine": .settings,
        "setup": .checklist, "keys": .key, "storage": .storage, "diagnostics": .info,
    ]
}
