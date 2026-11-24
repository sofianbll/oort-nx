import Foundation
import Combine
import Darwin

public final class AppSettingsStore: ObservableObject {
    @Published public var settings: AppSettings {
        didSet {
            if settings.lastSelectedGameID != oldValue.lastSelectedGameID {
                lastSelectedGameID = settings.lastSelectedGameID
            }
            save()
        }
    }

    @Published public private(set) var draft: AppSettingsDraft?
    /// Read by the Settings screen only. Background consumers continue to read committed settings.
    public var editingSettings: AppSettings {
        get { draft?.displayed(over: settings, previewsOnly: false) ?? settings }
        set {
            let visible = editingSettings
            draft?.update(from: visible, to: newValue)
        }
    }
    public var presentation: AppSettings { draft?.displayed(over: settings, previewsOnly: true) ?? settings }

    public func beginDraft(fields: [AppSettingsDraft.Field]) {
        if draft == nil { draft = AppSettingsDraft(settings, fields: fields) }
    }

    public func endDraft() { draft = nil }

    /// The same rename and read-back cover every changed field. No observer gets unverified values.
    public func commitDraft() throws {
        guard let draft, draft.hasChanges else { return }
        let memory = snapshotForWrite()
        let revision = nextWriteRevision()
        let saved = try writer.sync {
            try withWriteLock {
                let bytes = try readDisk()
                var disk = try bytes.map { try JSONDecoder().decode(AppSettings.self, from: $0) } ?? AppSettings()
                if bytes == lastDiskBytes { disk.lastSelectedGameID = memory.lastSelectedGameID }
                let merged = try draft.merging(memory: memory, disk: disk)
                try replace(merged, ifUnchangedFrom: bytes)
                return merged
            }
        }
        isLoading = true
        settings = saved
        isLoading = false
        self.draft = draft.restarting(from: saved)
        publish((nil, nil), revision: revision)
    }

    /// Navigation state. Publishing it as a settings change re-enters the view graph during a row move.
    public private(set) var lastSelectedGameID: UUID?

    public enum ErrorKind { case reading, writing }
    @Published public private(set) var loadError: String?
    public private(set) var errorKind: ErrorKind?
    public private(set) var recoveryFileURL: URL?
    public let fileURL: URL
    private let fileManager: FileManager
    private var isLoading = false
    // The main thread owns the snapshots and their revision. The writer serializes file replacement.
    private let writer = DispatchQueue(label: "local.nxlibrary.settings-write", qos: .utility)
    private var writeRevision = 0
    private var pendingSelectionWrite: DispatchWorkItem?
    private var needsRecoveryCopy = false
    // Only the serial writer changes this after initialization; normal writes must not trample external edits.
    private var lastDiskBytes: Data?

    public init(fileURL: URL = AppSettingsStore.defaultURL(),
                fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.settings = AppSettings()
        load()
    }

    public static func defaultURL() -> URL {
        AppData.supportRoot.appendingPathComponent("settings.json")
    }

    @discardableResult public func save() -> Bool {
        guard !isLoading else { return true }
        let revision = nextWriteRevision()
        let snapshot = snapshotForWrite()
        let outcome = writer.sync { write(snapshot) }
        publish(outcome, revision: revision)
        return outcome.error == nil
    }

    /// Update the restore choice without invalidating settings observers or writing on the animation thread.
    @MainActor public func rememberLastSelectedGame(_ id: UUID) {
        guard lastSelectedGameID != id else { return }
        lastSelectedGameID = id

        let revision = nextWriteRevision()
        let snapshot = snapshotForWrite()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let outcome = self.write(snapshot)
            DispatchQueue.main.async { [weak self] in self?.publish(outcome, revision: revision) }
        }
        pendingSelectionWrite = work
        writer.async(execute: work)
    }

    /// Quitting can overtake the queued write. Save the latest value before exiting.
    @MainActor public func flushPendingSelection() {
        if pendingSelectionWrite != nil { save() }
    }

    private func snapshotForWrite() -> AppSettings {
        var snapshot = settings
        snapshot.lastSelectedGameID = lastSelectedGameID
        return snapshot
    }

    private func nextWriteRevision() -> Int {
        pendingSelectionWrite?.cancel()
        pendingSelectionWrite = nil
        writeRevision += 1
        return writeRevision
    }

    private func write(_ snapshot: AppSettings) -> (recovery: URL?, error: Error?) {
        var recovery: URL?
        do {
            try withWriteLock {
                guard try readDisk() == lastDiskBytes else { throw AppSettingsDraft.Failure.changedElsewhere }
                recovery = try preserveUnreadableFile()
                try replace(snapshot, ifUnchangedFrom: lastDiskBytes)
            }
            return (recovery, nil)
        } catch {
            return (recovery, error)
        }
    }

    private func readDisk() throws -> Data? {
        do { return try Data(contentsOf: fileURL) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    private func withWriteLock<T>(_ operation: () throws -> T) throws -> T {
        let folder = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let lock = folder.appendingPathComponent(".\(fileURL.lastPathComponent).lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        return try operation()
    }

    private func replace(_ snapshot: AppSettings, ifUnchangedFrom expected: Data?) throws {
        let data = try JSONEncoder().encode(snapshot)
        // Decode before replacing the last good file. Read the same bytes back before publishing.
        guard try JSONDecoder().decode(AppSettings.self, from: data) == snapshot else {
            throw AppSettingsDraft.Failure.verification
        }
        let temp = fileURL.deletingLastPathComponent().appendingPathComponent(".settings-\(UUID()).tmp")
        defer { try? fileManager.removeItem(at: temp) }
        try data.write(to: temp)
        guard try readDisk() == expected else { throw AppSettingsDraft.Failure.changedElsewhere }
        guard rename(temp.path, fileURL.path) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard try readDisk() == data else { throw AppSettingsDraft.Failure.verification }
        lastDiskBytes = data
    }

    private func publish(_ outcome: (recovery: URL?, error: Error?), revision: Int) {
        if let copied = outcome.recovery { recoveryFileURL = copied }
        guard writeRevision == revision else { return }
        pendingSelectionWrite = nil
        if let error = outcome.error {
            errorKind = .writing
            loadError = error.localizedDescription
        } else {
            errorKind = nil
            if loadError != nil { loadError = nil }
        }
    }

    public func dismissError() {
        errorKind = nil
        loadError = nil
    }

    private func preserveUnreadableFile() throws -> URL? {
        guard needsRecoveryCopy else { return nil }
        let copy = fileURL.deletingLastPathComponent()
            .appendingPathComponent("settings.unreadable-\(UUID()).json")
        try fileManager.copyItem(at: fileURL, to: copy)
        needsRecoveryCopy = false
        return copy
    }

    private func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try Data(contentsOf: fileURL)
            lastDiskBytes = data
            settings = try JSONDecoder().decode(AppSettings.self, from: data)
            loadError = nil
        } catch {
            settings = AppSettings()
            needsRecoveryCopy = true
            recoveryFileURL = try? preserveUnreadableFile()
            errorKind = .reading
            loadError = error.localizedDescription
        }
    }
}
