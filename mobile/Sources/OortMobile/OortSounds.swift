import AVFoundation
import Observation
#if os(iOS) && !targetEnvironment(macCatalyst)
import UIKit
#endif

/// The interface sounds and their settings. The notes are made by `OortSynth`, as on the Mac; nothing is loaded.
@MainActor @Observable public final class OortSounds {
    public static let packs = ["oort", "pollen", "umbra", "impulsion"]
    private static let onKey = "oort.sounds", packKey = "oort.soundPack", hapticsKey = "oort.haptics"
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var players: [String: AVAudioPlayer] = [:]
    @ObservationIgnored private var step = 0
    @ObservationIgnored private var lastMove = Date.distantPast
    @ObservationIgnored private var ready = false

    /// What a finger feels, also when the sounds are off.
    public var haptics: Bool { didSet { defaults.set(haptics, forKey: Self.hapticsKey) } }
    public var isOn: Bool { didSet { defaults.set(isOn, forKey: Self.onKey) } }
    public var pack: String { didSet { defaults.set(pack, forKey: Self.packKey); players = [:] } }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        haptics = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
        isOn = defaults.object(forKey: Self.onKey) as? Bool ?? true
        pack = defaults.string(forKey: Self.packKey).flatMap { Self.packs.contains($0) ? $0 : nil } ?? "oort"
    }

    private func touch(_ event: SoundPackEvent) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard haptics else { return }
        switch event {
        case .move: UISelectionFeedbackGenerator().selectionChanged()
        case .select, .open, .back, .close: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .play, .resume, .confirm: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .deny: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .notification, .boot, .ambience: break
        }
        #endif
    }

    public func play(_ event: SoundPackEvent) {
        touch(event)
        guard isOn else { return }
        let now = Date()
        if event == .move {
            // A held direction repeats faster than the note is worth hearing; after a rest the notes start again.
            guard now.timeIntervalSince(lastMove) >= 0.06 else { return }
            step = now.timeIntervalSince(lastMove) < 0.9 ? (step + 1) % 8 : 0
            lastMove = now
        }
        let key = event == .move ? "move.\(step)" : event.rawValue
        let player: AVAudioPlayer
        if let known = players[key] { player = known } else {
            guard let data = OortSynth(pack: pack)?.wav(event, step: step), let made = try? AVAudioPlayer(data: data) else { return }
            players[key] = made
            player = made
        }
        #if os(iOS)
        // Ambient: the silent switch and the player's own music win.
        if !ready { try? AVAudioSession.sharedInstance().setCategory(.ambient) }
        #endif
        ready = true
        player.volume = 0.6
        player.currentTime = 0
        player.play()
    }
}
