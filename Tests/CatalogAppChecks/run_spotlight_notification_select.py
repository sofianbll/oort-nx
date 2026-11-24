#!/usr/bin/env python3
"""Drive the actual Spotlight selection observer with synthetic router updates."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2] / 'Sources/NXLibrary/Views/Spotlight'
view = (ROOT / 'SpotlightView.swift').read_text()
inputs = (ROOT / 'SpotlightView+Input.swift').read_text()
shell = (ROOT.parent / 'Shell/AppShellView.swift').read_text()
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
final class Spotlight {
    let router = Router()
    let content = Content()
    var state = State()
    var selected: UUID?
    func mutate(_ action: (inout State) -> Void) { action(&state) }
    func selectGame(_ id: UUID) { selected = id }
    func noticeSucceeded(_ id: UUID) {
        // SUCCESS
    }
    // CONSUME
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
    mounted.router.route = .library
    mounted.render()
    precondition(mounted.selected == c && mounted.router.pendingSpotlightSelect == nil)
    mounted.render()
}
print("Spotlight: selection arrives while mounted and waits under both overlay routes")
'''
with tempfile.TemporaryDirectory(prefix='oort-spotlight-select-') as directory:
    source = Path(directory) / 'main.swift'
    executable = Path(directory) / 'check'
    source.write_text(host.replace('// CONSUME', consume).replace('// SUCCESS', success)
                      .replace('// OBSERVERS', observers.replace('{ consumePendingSelect()', '{ self.consumePendingSelect()')))
    subprocess.run(['xcrun', 'swiftc', source, '-o', executable], check=True)
    subprocess.run([executable], check=True)
