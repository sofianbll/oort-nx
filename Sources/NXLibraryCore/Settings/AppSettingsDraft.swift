import Foundation

/// The editable fields, not the file schema: derived, migration and navigation keys aren't editable.
public struct AppSettingsDraft {
    public struct Field {
        public let id: String
        public let previews: Bool
        public let important: Bool
        fileprivate let differs: (AppSettings, AppSettings) -> Bool
        fileprivate let copy: (AppSettings, inout AppSettings) -> Void
        fileprivate let describe: (AppSettings) -> String

        public init<Value: Equatable>(_ id: String, _ key: WritableKeyPath<AppSettings, Value>,
                                      previews: Bool = false, important: Bool = false,
                                      describe: @escaping (Value) -> String) {
            self.id = id
            self.previews = previews
            self.important = important
            differs = { $0[keyPath: key] != $1[keyPath: key] }
            copy = { $1[keyPath: key] = $0[keyPath: key] }
            self.describe = { describe($0[keyPath: key]) }
        }
    }

    public struct Change: Identifiable {
        public let id: String
        public let before: String
        public let after: String
    }

    public enum Failure: LocalizedError, Equatable {
        case changedElsewhere
        case verification

        public var errorDescription: String? {
            switch self {
            case .changedElsewhere: "These settings changed elsewhere."
            case .verification: "The saved settings could not be verified."
            }
        }
    }

    private let fields: [Field]
    private let baseline: AppSettings
    public var values: AppSettings

    public init(_ baseline: AppSettings, fields: [Field]) {
        precondition(Set(fields.map(\.id)).count == fields.count)
        self.fields = fields.filter(\.important) + fields.filter { !$0.important }
        self.baseline = baseline
        self.values = baseline
    }

    private var edited: [Field] { fields.filter { $0.differs(baseline, values) } }
    public var hasChanges: Bool { fields.contains { $0.differs(baseline, values) } }

    public var changes: [Change] {
        edited.map { Change(id: $0.id, before: $0.describe(baseline), after: $0.describe(values)) }
    }

    /// Overlay only editable fields, leaving state remembered elsewhere (e.g. the current game) alone.
    public func displayed(over current: AppSettings, previewsOnly: Bool) -> AppSettings {
        var result = current
        for field in edited where !previewsOnly || field.previews { field.copy(values, &result) }
        return result
    }

    mutating func update(from visible: AppSettings, to proposed: AppSettings) {
        for field in fields where field.differs(visible, proposed) { field.copy(proposed, &values) }
    }

    func merging(memory: AppSettings, disk: AppSettings) throws -> AppSettings {
        var result = disk
        for field in edited {
            guard !field.differs(baseline, memory) && !field.differs(baseline, disk) else {
                throw Failure.changedElsewhere
            }
            field.copy(values, &result)
        }
        return result
    }

    func restarting(from current: AppSettings) -> Self { Self(current, fields: fields) }
}
