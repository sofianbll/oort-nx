import Foundation
import AppKit
import AVFoundation
import Combine
import NXLibraryCore

/// The older call-site names, each played as a Selene cue.
enum SoundEffectType: String, CaseIterable {
    case click
    case tabSwitch
    case focus
    case launch
    case error

    var cue: SoundCue {
        switch self {
        case .click: return .select
        case .tabSwitch, .focus: return .move
        case .launch: return .gameStarting
        case .error: return .alert
        }
    }
}

/// Owns playback and applies existing audio settings on its serial queue.
final class SoundEffectService {
    static let shared = SoundEffectService()

    private var cancellable: AnyCancellable?
    private var focusObserver: AnyCancellable?
    /// Starting a player blocks for a few milliseconds (the audio server's
    /// handshake), so the players live and play on a queue of their own: a move
    /// never holds up the frame that draws it.
    private let audio = DispatchQueue(label: "local.nxlibrary.sounds", qos: .userInteractive)
    private var enabled = true
    private var gain: Float = 0.6
    private var quieted = false
    private var foreground = true
    private var nativeRunning = false
    private var steamRunning = false
    private var returnPending = false
    private var isPlayingGame: Bool { nativeRunning || steamRunning }
    private var selected = "selene"
    private var pack: SoundPack?
    private var current: AVAudioPlayer?
    private var players: [SoundCue: AVAudioPlayer] = [:]
    private var lastMove = Date.distantPast
    private let library = SoundPackLibrary()
    private let resolver = SoundCueResolver(
        importedSounds: SeleneImporter.defaultDestination.appendingPathComponent("Sounds"),
        bundledSounds: Bundle.main.resourceURL?.appendingPathComponent("Selene/Sounds"))

    private init() {}

    /// Follows the settings store from now on.
    @MainActor
    func bind(to store: AppSettingsStore) {
        cancellable = store.$settings.combineLatest(store.$draft)
            .map { committed, draft in draft?.displayed(over: committed, previewsOnly: true) ?? committed }
            .map { ($0.interfaceSounds, $0.soundVolume, $0.soundPackID) }
            .removeDuplicates { $0 == $1 }
            .sink { enabled, volume, id in
                self.audio.async {
                    self.enabled = enabled
                    self.gain = volume.isFinite ? Float(min(max(volume, 0), 1)) : 0
                    if self.selected != id {
                        self.stopPlayers()
                        self.returnPending = false
                        self.selected = id
                        self.pack = try? self.library.load(id)
                    }
                    if !enabled || self.gain == 0 {
                        self.stopPlayers()
                        self.returnPending = false
                    } else {
                        self.current?.volume = self.gain
                        self.players.values.forEach { $0.volume = self.gain }
                    }
                }
            }
        let center = NotificationCenter.default
        focusObserver = center.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in true }
            .merge(with: center.publisher(for: NSApplication.didResignActiveNotification).map { _ in false })
            .sink { self.setForeground($0) }
        setForeground(NSApplication.shared.isActive)
    }

    private func setForeground(_ active: Bool) {
        audio.async {
            self.foreground = active
            if !active { self.stopPlayers() }
            self.playReturnIfReady()
        }
    }

    func setQuietLaunch(_ quiet: Bool) {
        audio.async {
            self.quieted = quiet
            self.playReturnIfReady()
        }
    }

    func setGameRunning(_ running: Bool, steam: Bool = false) {
        audio.async {
            let wasRunning = self.isPlayingGame
            if steam { self.steamRunning = running } else { self.nativeRunning = running }
            if self.isPlayingGame {
                self.returnPending = false
                self.stopPlayers()
            } else if wasRunning {
                self.returnPending = self.pack != nil && self.enabled && self.gain > 0
                self.playReturnIfReady()
            }
        }
    }

    private func playReturnIfReady() {
        guard returnPending, foreground, !isPlayingGame, !quieted else { return }
        returnPending = false
        playOnQueue(.resume)
    }

    /// Drops loaded players so freshly imported sounds are picked up.
    func reloadSounds() {
        audio.async {
            self.stopPlayers()
            self.players = [:]
        }
    }

    func play(_ effect: SoundEffectType) {
        if effect == .error { play(.deny, legacy: .alert) }
        else { play(effect.cue) }
    }

    func play(_ cue: SoundCue) {
        let event: SoundPackEvent?
        switch cue {
        case .move: event = .move
        case .select: event = .select
        case .back: event = .back
        case .openPanel: event = .open
        case .gameStarting: event = .play
        case .gameReady: event = nil // Game readiness is not a return to the launcher.
        case .alert: event = .notification
        case .success: event = .success
        case .key: event = .confirm
        case .boot: event = .boot
        }
        audio.async { self.playOnQueue(event, legacy: cue) }
    }

    func play(_ event: SoundPackEvent, legacy cue: SoundCue) {
        audio.async { self.playOnQueue(event, legacy: cue) }
    }

    func preview(_ event: SoundPackEvent) {
        audio.async { self.playOnQueue(event, legacy: event.legacyCue, preview: true) }
    }

    private func playOnQueue(_ event: SoundPackEvent?, legacy cue: SoundCue? = nil, preview: Bool = false) {
        guard enabled, gain > 0, !isPlayingGame, foreground || (pack == nil && !preview) else { return }
        guard !quieted || cue == .gameStarting || cue == .gameReady else { return }
        if event == .move && !preview {
            // A held stick repeats faster than the cue is worth hearing.
            let now = Date()
            guard now.timeIntervalSince(lastMove) >= 0.06 else { return }
            lastMove = now
        }
        let chosen: AVAudioPlayer?
        if let pack {
            guard let event else { return }
            if selected == "oort", !preview, event == .deny { return }
            if let bytes = pack.audio(for: event), let player = try? AVAudioPlayer(data: bytes) {
                chosen = player
            } else {
                guard event != .boot, event != .ambience,
                      !(selected == "oort" && event == .move) else { return }
                chosen = cue.flatMap(player(for:))
            }
            if let chosen {
                current?.stop()
                current = chosen
            }
        } else {
            chosen = cue.flatMap(player(for:))
            if preview, let chosen {
                stopPlayers()
                current = chosen
            }
        }
        guard let chosen else { return }
        chosen.volume = gain
        chosen.currentTime = 0
        chosen.play()
    }

    private func stopPlayers() {
        current?.stop()
        current = nil
        players.values.forEach { $0.stop() }
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        if let player = players[cue] { return player }
        guard let url = resolver.url(for: cue),
              let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[cue] = player
        return player
    }
}
