import Foundation

/// How the launch screen is left by hand. The first seconds belong to the game, so a press meant for the screen
/// before it never closes the screen; after that it says what closes it, and only that does.
public enum LaunchExit {
    public static let offerDelay: TimeInterval = 4

    /// What the screen names: a key or a button only while Oort receives them, else the click that always works.
    public enum Offer: Equatable, Sendable { case none, button, click }

    public static func offer(elapsed: TimeInterval, appActive: Bool) -> Offer {
        guard elapsed >= offerDelay else { return .none }
        return appActive ? .button : .click
    }
}
