import Foundation
import CoreGraphics

struct RectValue: Codable, Hashable, Sendable {
    var x: Double; var y: Double; var width: Double; var height: Double
    init(_ rect: CGRect) { x = rect.origin.x; y = rect.origin.y; width = rect.width; height = rect.height }
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct DisplayIdentity: Codable, Hashable, Sendable {
    let stableID: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
}

struct DisplayDescriptor: Codable, Hashable, Sendable {
    let identity: DisplayIdentity
    let bounds: RectValue
    let scale: Double
    let rotation: Double
    let isPrimary: Bool
}

struct DisplayConfiguration: Codable, Hashable, Sendable {
    static let schemaVersion = 1
    let schemaVersion: Int
    let displays: [DisplayDescriptor]
    var fingerprint: String { displays.map { "\($0.identity.stableID):\($0.bounds.width)x\($0.bounds.height):\($0.scale):\($0.rotation):\($0.isPrimary)" }.joined(separator: "|") }
}

struct WindowKey: Codable, Hashable, Sendable {
    let accessibilityIdentifier: String?
    let documentURL: String?
    let normalizedTitle: String
    let role: String
    let subrole: String
    let ordinal: Int
}

struct WindowSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let bundleIdentifier: String
    let key: WindowKey
    let sourceDisplayID: String
    /// Frame expressed as percentages of its source display's usable frame.
    let relativeFrame: RectValue
    let wasMinimized: Bool
}

struct LayoutSnapshot: Codable, Identifiable, Sendable {
    let id: UUID
    let configuration: DisplayConfiguration
    let capturedAt: Date
    let windows: [WindowSnapshot]
}

struct RestoreResult: Sendable {
    var moved = 0; var alreadyCorrect = 0; var unmatched = 0; var ambiguous = 0; var unsupported = 0; var failed = 0
    var summary: String { "Moved \(moved) · Already correct \(alreadyCorrect) · Unmatched \(unmatched) · Ambiguous \(ambiguous) · Unsupported \(unsupported) · Failed \(failed)" }
}

enum SnapshotError: LocalizedError { case unsupportedVersion, corrupted
    var errorDescription: String? { self == .unsupportedVersion ? "This snapshot was created by a newer version of Window Saver." : "The saved snapshot could not be read." }
}
