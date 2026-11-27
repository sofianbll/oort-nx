import AppKit
import ArcanePorting
import Combine
import NXLibraryCore

/// Draws the running build or transfer as a bar on the Dock icon, and nothing when no work runs.
@MainActor
final class DockProgress {
    private var changes: AnyCancellable?
    private var shown: Int?

    init(_ viewModel: AppViewModel) {
        let cloud = viewModel.cloudLibrary
        changes = Publishers.Merge3(viewModel.objectWillChange.map { _ in () },
                                    viewModel.porting.objectWillChange.map { _ in () },
                                    cloud.objectWillChange.map { _ in () })
            // The values are read after the change, at most twice a second.
            .throttle(for: .milliseconds(500), scheduler: RunLoop.main, latest: true)
            .sink { [weak self, weak viewModel] in
                guard let self, let viewModel else { return }
                MainActor.assumeIsolated { self.show(Self.percent(viewModel)) }
            }
    }

    static func percent(_ viewModel: AppViewModel) -> Int? {
        let cloud = viewModel.cloudLibrary
        var running: [Double?] = []
        if viewModel.isBuilding { running.append(viewModel.portingProgress?.overall) }
        if let id = cloud.active?.request.id {
            running.append(CloudTransferPresentation.fraction(cloud.states[id]?.progress))
        }
        if let move = cloud.libraryMove { running.append(move.fraction) }
        return DockProgressValue.percent(running)
    }

    private func show(_ percent: Int?) {
        guard percent != shown else { return }
        shown = percent
        let tile = NSApplication.shared.dockTile
        if let percent {
            let view = (tile.contentView as? DockProgressView) ?? DockProgressView()
            view.fraction = CGFloat(percent) / 100
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.display()
    }
}

/// The app's own icon with a bar near its foot, as the Finder draws a copy.
private final class DockProgressView: NSView {
    var fraction: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        NSApplication.shared.applicationIconImage?.draw(in: bounds)
        let height = bounds.height * 0.09
        let track = NSRect(x: bounds.width * 0.14, y: bounds.height * 0.16, width: bounds.width * 0.72, height: height)
        let radius = height / 2
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: track.insetBy(dx: -height * 0.2, dy: -height * 0.2),
                     xRadius: radius * 1.2, yRadius: radius * 1.2).fill()
        NSColor.white.setFill()
        var bar = track
        bar.size.width = max(height, track.width * fraction)
        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
    }
}
