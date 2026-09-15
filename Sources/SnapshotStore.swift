import Foundation

protocol SnapshotStoring: Sendable {
    func load() throws -> [String: LayoutSnapshot]
    func save(_ snapshots: [String: LayoutSnapshot]) throws
}

final class SnapshotStore: SnapshotStoring, @unchecked Sendable {
    private let url: URL
    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WindowSaver", isDirectory: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("snapshots.json")
    }
    func load() throws -> [String: LayoutSnapshot] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let snapshots = try JSONDecoder.windowSaver.decode([String: LayoutSnapshot].self, from: Data(contentsOf: url))
            guard snapshots.values.allSatisfy({ $0.configuration.schemaVersion <= DisplayConfiguration.schemaVersion }) else { throw SnapshotError.unsupportedVersion }
            return snapshots
        } catch let error as SnapshotError { throw error } catch { throw SnapshotError.corrupted }
    }
    func save(_ snapshots: [String: LayoutSnapshot]) throws {
        let data = try JSONEncoder.windowSaver.encode(snapshots)
        try data.write(to: url, options: [.atomic])
    }
}
extension JSONEncoder { static var windowSaver: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e } }
extension JSONDecoder { static var windowSaver: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
