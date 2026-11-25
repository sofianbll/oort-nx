import Foundation

/// A way to read the library that the player may turn on. The core knows none by name: an app lists the ones it was built with,
/// so leaving one out means leaving out one line and its module.
public struct ShelfConnector: Sendable {
    public enum Permission: String, CaseIterable, Sendable { case network, readLibrary, storeBuilds }

    public let id: String
    /// Every host it may speak to, for the screen that asks the player and for the test that checks it.
    public let hosts: [String]
    public let permissions: Set<Permission>
    let open: @Sendable () async throws -> any ShelfSource
    let forget: @Sendable () async throws -> Void

    /// Erases the credential and leaves the choice as it is.
    public func forgetAll() async throws { try await forget() }

    /// `forget` erases what the connector kept on the device (its credential).
    public init(id: String, hosts: [String], permissions: Set<Permission>, open: @escaping @Sendable () async throws -> any ShelfSource,
                forget: @escaping @Sendable () async throws -> Void) {
        self.id = id
        self.hosts = hosts
        self.permissions = permissions
        self.open = open
        self.forget = forget
    }
}

/// Where the player's choices are kept.
public protocol ShelfChoices: Sendable {
    func permissions(of connector: String) -> Set<String>?
    func set(_ permissions: Set<String>?, of connector: String)
}

/// Every connector is off until the player turns it on, with the permissions that were shown. Nothing is opened before that.
public struct ShelfConnectors: Sendable {
    public let all: [ShelfConnector]
    let choices: any ShelfChoices

    public init(_ all: [ShelfConnector], choices: any ShelfChoices) {
        self.all = all
        self.choices = choices
    }

    /// An app update that asks for more turns the connector off again until the player agrees.
    public func isOn(_ id: String) -> Bool {
        guard let connector = connector(id), let granted = choices.permissions(of: id) else { return false }
        return Set(connector.permissions.map(\.rawValue)).isSubset(of: granted)
    }

    public func turnOn(_ id: String, granting permissions: Set<ShelfConnector.Permission>) throws {
        guard let connector = connector(id), connector.permissions.isSubset(of: permissions) else { throw ShelfError.sourceOff }
        choices.set(Set(permissions.map(\.rawValue)), of: id)
    }

    /// Off first, then forgotten: a failure to erase never leaves it on.
    public func turnOff(_ id: String) async throws {
        choices.set(nil, of: id)
        try await connector(id)?.forget()
    }

    public func source(_ id: String) async throws -> any ShelfSource {
        guard isOn(id), let connector = connector(id) else { throw ShelfError.sourceOff }
        return try await connector.open()
    }

    private func connector(_ id: String) -> ShelfConnector? { all.first { $0.id == id } }
}
