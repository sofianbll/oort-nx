import ShellHost

/// Why a game did not start, in the player's words. The host's own message names the signature for every load failure:
/// that is said only when the system says so.
public enum OortLaunchWords {
    public static func why(_ raw: String) -> String {
        let signature = ["code signature", "Team ID", "sandbox blocked mmap", "not valid for use in process"]
        guard raw.hasPrefix("The game's code could not be loaded:"), !signature.contains(where: raw.contains) else { return localizeEngineLaunchError(raw) }
        return Oort.text("This game's code could not be loaded. Build it again on your Mac, then add it again.")
    }
}
