#!/usr/bin/env python3
"""Drive the actual Spotlight selection observer with synthetic router updates."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[4] / 'apps/mac/OortMac/Views/Spotlight'
view = (ROOT / 'SpotlightView.swift').read_text()
inputs = (ROOT / 'SpotlightView+Input.swift').read_text()
shell = (ROOT.parent / 'Shell/AppShellView.swift').read_text()
add_game = (ROOT.parent / 'AddGame/AddGameView.swift').read_text()
close = add_game[add_game.index('    private func close(then'):add_game.index('    // MARK: - Input')]
close_path = add_game[add_game.index('    private func requestClose()'):add_game.index('    private func drop(')]
porting = (ROOT.parents[1] / 'ViewModels/PortingModel+AddGame.swift').read_text()
closing_rule = porting[porting.index('    static func closingAsks('):].split('\n    }', 1)[0] + '\n    }'
notification = shell[shell.index('publisher(for: .nxLibraryPortingNoticeOpened)'):
                     shell.index('publisher(for: .nxLibraryOpenLibrary)')]
success = notification.rsplit('\n            } else {\n', 1)[1].split('\n            }', 1)[0]
consume = inputs[inputs.index('    func consumePendingSelect('):inputs.index('    /// Selects a game in the row')]
observers = '\n'.join(line for line in view.splitlines()
                      if '.onChange(of:' in line and 'consumePendingSelect()' in line)
host = '''
import Foundation
enum Route {
    case library, profile, addGame, console
    var isOverlay: Bool { self == .addGame || self == .console }
}
final class Router {
    var route = Route.library
    var underlyingRoute = Route.library
    var previousRoute: Route? = nil
    var pendingSpotlightSelect: UUID?
    func showLibrary() { route = .library }
    func back() { route = underlyingRoute }
    func requestSpotlightSelect(_ id: UUID) { pendingSpotlightSelect = id }
}
final class Content {
    var previous: UUID?
    var callback: (() -> Void)?
    func onChange(of value: UUID?, _ callback: @escaping () -> Void) -> Self {
        if previous != value { self.callback = callback }
        previous = value
        return self
    }
    func renderCompleted() {
        let changed = callback
        callback = nil
        changed?()
    }
}
struct State {
    var details = false
    mutating func showGameDetails() -> Bool { details = true; return true }
}
final class PortingModel {
    var buildSuccessPath: URL?
    var selectedGameFolder: URL?
    var selectedSources: [URL] = []
    func startNewAddGame() {}
    func addGameDidLeave() {}
    // CLOSING_RULE
}
struct ViewModel {
    var portingGameID: UUID?
    var isBuilding: Bool { portingGameID != nil }
}
struct SoundEffectService {
    enum Sound { case alert }
    static let shared = Self()
    func play(_ sound: Sound) {}
}
final class Spotlight {
    enum Focus { case cancel }
    let router = Router()
    let porting = PortingModel()
    var viewModel = ViewModel()
    var editing: String?
    var confirmFocus = Focus.cancel
    var confirmDiscard = false
    let content = Content()
    var state = State()
    var selected: UUID?
    func mutate(_ action: (inout State) -> Void) { action(&state) }
    func selectGame(_ id: UUID) { selected = id }
    func noticeSucceeded(_ id: UUID) {
        // SUCCESS
    }
    // CONSUME
    // CLOSE
    // CLOSE_PATH
    func closeAddGame() { requestClose() }
    func render() {
        _ = content
        // OBSERVERS
        content.renderCompleted()
    }
}
let mounted = Spotlight()
let a = UUID(), b = UUID(), c = UUID()
mounted.selectGame(a)
mounted.render()
mounted.noticeSucceeded(b)
mounted.render()
guard mounted.selected == b, mounted.router.pendingSpotlightSelect == nil else {
    print("FAIL: a selection request on already-mounted Spotlight is not delivered")
    exit(1)
}
for overlay in [Route.addGame, .console] {
    mounted.router.route = overlay
    mounted.noticeSucceeded(c)
    precondition(mounted.router.route == overlay)
    mounted.render()
    mounted.consumePendingSelect() // onAppear can run behind an overlay
    precondition(mounted.router.pendingSpotlightSelect == c)
    if overlay == .addGame {
        mounted.viewModel.portingGameID = a
        mounted.closeAddGame()
    } else {
        mounted.router.back()
    }
    mounted.render()
    guard mounted.selected == c && mounted.router.pendingSpotlightSelect == nil else {
        print("FAIL: closing Add Game replaces the notified game with the ongoing port")
        exit(1)
    }
    mounted.render()
}
mounted.router.route = .addGame
mounted.closeAddGame()
mounted.render()
precondition(mounted.selected == a, "An ongoing port is still selected when no request is pending")
print("Spotlight: notification wins over the ongoing port when Add Game closes")
'''
with tempfile.TemporaryDirectory(prefix='oort-spotlight-select-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// CONSUME', consume).replace('// SUCCESS', success)
                      .replace('// CLOSING_RULE', closing_rule).replace('// CLOSE_PATH', close_path).replace('// CLOSE', close)
                      .replace('// OBSERVERS', observers.replace('{ consumePendingSelect()', '{ self.consumePendingSelect()')))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
