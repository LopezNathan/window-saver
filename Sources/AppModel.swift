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
    private var activeApplication: NSRunningApplication?
    @Published private(set) var activeApplicationName = "Active Application"
    private lazy var coordinator = RestoreCoordinator(displays: topology, accessibility: accessibility)
    init() {
        configuration = topology.currentConfiguration()
        do { snapshots = try store.load() } catch { diagnostic = error.localizedDescription }
        permissionGranted = accessibility.isTrusted()
        recordActiveApplication(NSWorkspace.shared.frontmostApplication)
        coordinator.snapshotProvider = { [weak self] in self?.snapshots[self?.configuration.fingerprint ?? ""] }
        coordinator.onResult = { [weak self] result in self?.diagnostic = result.summary }
        topology.startObserving { [weak self] in Task { @MainActor in self?.topologyChanged() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.restoreLaunchedApplication(app) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor in self?.recordActiveApplication(app) }
        }
    }
    var currentSnapshot: LayoutSnapshot? { snapshots[configuration.fingerprint] }
    var displayStatus: String { "\(configuration.displays.count) display\(configuration.displays.count == 1 ? "" : "s") · \(currentSnapshot == nil ? "No saved layout" : "Layout saved")" }
    func refreshActiveApplication() { recordActiveApplication(NSWorkspace.shared.frontmostApplication) }
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
    func updateActiveApplicationWindows() {
        guard permissionForSaving(), let app = activeApplication, let bundleID = app.bundleIdentifier else { return }
        let replacement = accessibility.captureWindows(for: app, in: configuration)
        guard !replacement.isEmpty else { diagnostic = "No controllable windows found for \(activeApplicationName)."; return }
        let existing = currentSnapshot?.windows.filter { $0.bundleIdentifier == bundleID } ?? []
        if !existing.isEmpty && !confirmReplacing("Replace saved windows for \(activeApplicationName)?", "This updates all \(existing.count) saved window\(existing.count == 1 ? "" : "s") for this app while keeping every other app’s layout.") { return }
        if updateSnapshot(removing: { $0.bundleIdentifier == bundleID }, adding: replacement) {
            diagnostic = "Updated \(replacement.count) window\(replacement.count == 1 ? "" : "s") for \(activeApplicationName)."
        }
    }
    func updateActiveWindow() {
        guard permissionForSaving(), let app = activeApplication else { return }
        guard let replacement = accessibility.captureFocusedWindow(for: app, in: configuration) else { diagnostic = "No controllable focused window found for \(activeApplicationName)."; return }
        if updateSnapshot(removing: { $0.bundleIdentifier == replacement.bundleIdentifier && $0.key == replacement.key }, adding: [replacement]) {
            diagnostic = "Updated the active window for \(activeApplicationName)."
        }
    }
    func restoreNow() { refreshPermission(); guard permissionGranted else { diagnostic = "Accessibility access is required to restore windows."; return }; coordinator.restoreNow() }
    private func recordActiveApplication(_ app: NSRunningApplication?) {
        guard let app = nonWindowSaverApplication(app) else { return }
        activeApplication = app
        activeApplicationName = app.localizedName ?? "Active Application"
    }
    private func nonWindowSaverApplication(_ app: NSRunningApplication?) -> NSRunningApplication? {
        app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app
    }
    private func permissionForSaving() -> Bool {
        guard permissionGranted else { requestAccessibility(); return false }
        return true
    }
    private func confirmReplacing(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: "Replace"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func updateSnapshot(removing shouldRemove: (WindowSnapshot) -> Bool, adding replacement: [WindowSnapshot]) -> Bool {
        let retained = currentSnapshot?.windows.filter { !shouldRemove($0) } ?? []
        let snapshot = LayoutSnapshot(id: UUID(), configuration: configuration, capturedAt: .now, windows: retained + replacement)
        snapshots[configuration.fingerprint] = snapshot
        do { try store.save(snapshots); automaticRestore = true; return true } catch { diagnostic = error.localizedDescription; return false }
    }
    private func topologyChanged() { configuration = topology.currentConfiguration(); diagnostic = "Display setup changed: \(displayStatus)"; if automaticRestore { coordinator.scheduleRestore() } }
    private func restoreLaunchedApplication(_ app: NSRunningApplication?) {
        guard automaticRestore, let bundleID = app?.bundleIdentifier, currentSnapshot?.windows.contains(where: { $0.bundleIdentifier == bundleID }) == true else { return }
        coordinator.restoreApplication(bundleIdentifier: bundleID)
    }
}
