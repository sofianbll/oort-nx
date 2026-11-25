import Foundation

extension CatalogNativeApplication {
    public init(_ observed: NativeMacApplication) {
        url = observed.url
        executableURL = observed.executableURL
        bundleIdentifier = observed.bundleIdentifier
        name = observed.name
        architectures = observed.architectures.sorted { $0.rawValue < $1.rawValue }
        isDeclaredGame = observed.isDeclaredGame
    }
}
