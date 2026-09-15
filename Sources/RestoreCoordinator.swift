import Foundation

@MainActor
final class RestoreCoordinator {
    private let displays: DisplayTopologyProviding
    private let accessibility: WindowAccessibilityProviding
    private var scheduled: Task<Void, Never>?
    var onResult: ((RestoreResult) -> Void)?
    var snapshotProvider: (() -> LayoutSnapshot?)?
    init(displays: DisplayTopologyProviding, accessibility: WindowAccessibilityProviding) { self.displays = displays; self.accessibility = accessibility }
    func scheduleRestore(after seconds: TimeInterval = 2) {
        scheduled?.cancel(); scheduled = Task { [weak self] in try? await Task.sleep(for: .seconds(seconds)); guard !Task.isCancelled else { return }; self?.restoreNow() }
    }
    func restoreNow() {
        guard let snapshot = snapshotProvider?() else { return }
        let configuration = displays.currentConfiguration()
        var result = RestoreResult()
        snapshot.windows.forEach { result.add(accessibility.restore($0, in: configuration)) }
        onResult?(result)
    }
    /// Polls only the just-launched application, allowing delayed Electron/browser windows to appear.
    func restoreApplication(bundleIdentifier: String) {
        Task { [weak self] in
            guard let self else { return }
            var completed = Set<UUID>()
            var cumulative = RestoreResult()
            for attempt in 0..<20 {
                guard !Task.isCancelled, let snapshot = self.snapshotProvider?() else { return }
                let configuration = self.displays.currentConfiguration()
                for window in snapshot.windows where window.bundleIdentifier == bundleIdentifier && !completed.contains(window.id) {
                    let result = self.accessibility.restore(window, in: configuration)
                    cumulative.add(result)
                    if result.moved > 0 || result.alreadyCorrect > 0 || result.ambiguous > 0 || result.unsupported > 0 { completed.insert(window.id) }
                }
                if completed.count == snapshot.windows.filter({ $0.bundleIdentifier == bundleIdentifier }).count { break }
                if attempt < 19 { try? await Task.sleep(for: .milliseconds(500)) }
            }
            self.onResult?(cumulative)
        }
    }
}
private extension RestoreResult { mutating func add(_ other: RestoreResult) { moved += other.moved; alreadyCorrect += other.alreadyCorrect; unmatched += other.unmatched; ambiguous += other.ambiguous; unsupported += other.unsupported; failed += other.failed } }
