import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var configuration: DisplayConfiguration
    @Published private(set) var snapshots: [String: LayoutSnapshot] = [:]
    @Published private(set) var permissionGranted = false
    @Published private(set) var diagnostic = "Ready"
    @Published var excludedBundleIDs: Set<String> = []
    @AppStorage("automaticRestore") var automaticRestore = false
    private let topology = DisplayTopologyService()
    private let accessibility = WindowAccessibilityService()
    private let store = SnapshotStore()
    private lazy var coordinator = RestoreCoordinator(displays: topology, accessibility: accessibility)
    init() {
        configuration = topology.currentConfiguration()
        do { snapshots = try store.load() } catch { diagnostic = error.localizedDescription }
        permissionGranted = accessibility.isTrusted()
        coordinator.snapshotProvider = { [weak self] in self?.snapshots[self?.configuration.fingerprint ?? ""] }
        coordinator.onResult = { [weak self] result in self?.diagnostic = result.summary }
        topology.startObserving { [weak self] in Task { @MainActor in self?.topologyChanged() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.restoreLaunchedApplication(app) }
        }
    }
    var currentSnapshot: LayoutSnapshot? { snapshots[configuration.fingerprint] }
    var displayStatus: String { "\(configuration.displays.count) display\(configuration.displays.count == 1 ? "" : "s") · \(currentSnapshot == nil ? "No saved layout" : "Layout saved")" }
    func requestAccessibility() { permissionGranted = accessibility.isTrusted(prompt: true); diagnostic = permissionGranted ? "Accessibility access granted." : "Grant Accessibility access in System Settings, then return here." }
    func refreshPermission() { permissionGranted = accessibility.isTrusted() }
    func saveCurrent() {
        guard permissionGranted else { requestAccessibility(); return }
        if currentSnapshot != nil {
            let alert = NSAlert()
            alert.messageText = "Replace saved layout?"
            alert.informativeText = "This replaces the current display setup’s existing window positions."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let windows = accessibility.captureWindows(in: configuration, excludedBundleIDs: excludedBundleIDs)
        let snapshot = LayoutSnapshot(id: UUID(), configuration: configuration, capturedAt: .now, windows: windows)
        snapshots[configuration.fingerprint] = snapshot
        do { try store.save(snapshots); automaticRestore = true; diagnostic = "Saved \(windows.count) controllable windows for this display setup." } catch { diagnostic = error.localizedDescription }
    }
    func restoreNow() { refreshPermission(); guard permissionGranted else { diagnostic = "Accessibility access is required to restore windows."; return }; coordinator.restoreNow() }
    private func topologyChanged() { configuration = topology.currentConfiguration(); diagnostic = "Display setup changed: \(displayStatus)"; if automaticRestore { coordinator.scheduleRestore() } }
    private func restoreLaunchedApplication(_ app: NSRunningApplication?) {
        guard automaticRestore, let bundleID = app?.bundleIdentifier, currentSnapshot?.windows.contains(where: { $0.bundleIdentifier == bundleID }) == true else { return }
        coordinator.restoreApplication(bundleIdentifier: bundleID)
    }
}
