import Foundation
import NXLibraryCore
import ArcanePorting

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard arguments.isEmpty || (arguments.count == 2 && arguments.first == "--fixture-home") else {
        FileHandle.standardError.write(Data("Usage: scripts/seed_trial2.sh [--fixture-home <path>]\n".utf8))
        exit(2)
    }
    let home = arguments.isEmpty ? FileManager.default.homeDirectoryForCurrentUser
        : URL(fileURLWithPath: arguments.last!, isDirectory: true)
    let profile = AppDataProfile(home: home, isDevelopment: true, isTrial2: true)
    try DevelopmentProfileImporter().seedTrial2(profile: profile)
    print("Copied the launcher library into \(profile.supportRoot.path).")
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
