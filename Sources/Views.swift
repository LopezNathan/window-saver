import SwiftUI

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Button("Save Current Window Positions") { model.saveCurrent() }
            .onAppear { model.refreshActiveApplication() }
        Button("Restore Windows") { model.restoreNow() }.disabled(model.currentSnapshot == nil)
        Divider()
        Text(model.activeApplicationName).foregroundStyle(.secondary)
        Button("Update All Windows for \(model.activeApplicationName)") { model.updateActiveApplicationWindows() }
        Button("Update Active Window") { model.updateActiveWindow() }
        Divider()
        Text(model.displayStatus).foregroundStyle(.secondary)
        Toggle("Automatic Restore", isOn: $model.automaticRestore)
        Divider()
        SettingsLink { Text("Settings & Diagnostics…") }
        Button("Quit Window Saver") { NSApplication.shared.terminate(nil) }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Window Saver").font(.title2.bold())
            GroupBox("Accessibility") {
                HStack { Image(systemName: model.permissionGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill").foregroundStyle(model.permissionGranted ? .green : .orange); Text(model.permissionGranted ? "Access granted" : "Access required to save and restore windows"); Spacer(); Button(model.permissionGranted ? "Refresh" : "Grant Access") { model.permissionGranted ? model.refreshPermission() : model.requestAccessibility() } }
            }
            GroupBox("Behavior") { Toggle("Restore automatically after display changes", isOn: $model.automaticRestore) }
            GroupBox("Current display setup") { VStack(alignment: .leading) { Text(model.displayStatus); if let snapshot = model.currentSnapshot { Text("Saved \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.windows.count) windows").foregroundStyle(.secondary) } } }
            GroupBox("Diagnostics") { Text(model.diagnostic).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 480).onAppear { model.refreshPermission() }
    }
}
