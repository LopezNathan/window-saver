import SwiftUI
import AppKit

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openSettings) private var openSettings
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
        Button("Stored Layouts & Settings…") {
            openSettings()
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
            }
        }
        Button("Quit Window Saver") { NSApplication.shared.terminate(nil) }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFingerprint: String?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedSnapshot: LayoutSnapshot? {
        guard let selectedFingerprint else { return model.currentSnapshot ?? model.savedSnapshots.first }
        return model.snapshot(for: selectedFingerprint) ?? model.currentSnapshot ?? model.savedSnapshots.first
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    if columnVisibility == .all {
                        configurationList
                            .frame(width: 235)
                        Divider()
                    }
                    detailContent
                }
                .frame(minHeight: 430)
                Divider()
                footer
            }
        }
        .frame(width: 900, height: 700)
        .onAppear {
            if selectedFingerprint == nil { selectedFingerprint = model.currentSnapshot?.configuration.fingerprint ?? model.savedSnapshots.first?.configuration.fingerprint }
            model.refreshPermission()
        }
        .onChange(of: model.configuration.fingerprint) { _, fingerprint in selectedFingerprint = fingerprint }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderless)
            .contentShape(Rectangle())
            .help(columnVisibility == .all ? "Hide display configurations" : "Show display configurations")
            .offset(x: -8)

            Image(systemName: "rectangle.3.group.fill")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.tint)
                .frame(width: 40, height: 40).background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Stored Window Layouts").font(.title3.weight(.semibold))
                Text("Browse the display setups Window Saver knows about.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if model.permissionGranted {
                Label("Accessibility enabled", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            } else { Button("Grant Access") { model.requestAccessibility() } }
        }
        .padding(.horizontal, 22).padding(.vertical, 15)
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .all ? .detailOnly : .all
    }

    private var configurationList: some View {
        List(selection: $selectedFingerprint) {
            Section("Display configurations") {
                ForEach(model.savedSnapshots) { snapshot in
                    ConfigurationRow(snapshot: snapshot, isCurrent: snapshot.configuration.fingerprint == model.configuration.fingerprint)
                        .tag(snapshot.configuration.fingerprint as String?)
                }
            }
        }.listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let snapshot = selectedSnapshot {
            LayoutDetail(snapshot: snapshot, isCurrent: snapshot.configuration.fingerprint == model.configuration.fingerprint)
                .id(snapshot.id)
        } else {
            ContentUnavailableView("No saved layouts", systemImage: "rectangle.on.rectangle.slash", description: Text("Save your current windows from the menu bar to create a display layout."))
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Restore automatically after display changes", isOn: $model.automaticRestore).font(.subheadline)
            Spacer()
            Text(model.diagnostic).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }
}

private struct ConfigurationRow: View {
    let snapshot: LayoutSnapshot; let isCurrent: Bool
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: snapshot.configuration.displays.count == 1 ? "display" : "display.2").foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.configuration.displays.count) Display\(snapshot.configuration.displays.count == 1 ? "" : "s")").fontWeight(isCurrent ? .semibold : .regular)
                Text("\(snapshot.windows.count) windows · \(snapshot.capturedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isCurrent { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Current display setup") }
        }.padding(.vertical, 3)
    }
}

private struct LayoutDetail: View {
    let snapshot: LayoutSnapshot; let isCurrent: Bool
    @State private var presentedContents: SavedContents?
    private var displays: [DisplayDescriptor] { snapshot.configuration.displays }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 7) {
                            Text(isCurrent ? "Current display setup" : "Saved display setup").font(.title3.weight(.semibold))
                            if isCurrent { Text("ACTIVE").font(.caption2.weight(.bold)).foregroundStyle(.green).padding(.horizontal, 6).padding(.vertical, 3).background(.green.opacity(0.12), in: Capsule()) }
                        }
                        Text("Saved \(snapshot.capturedAt.formatted(date: .complete, time: .shortened))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("\(snapshot.windows.count) saved windows", systemImage: "macwindow.stack").font(.subheadline.weight(.medium))
                }
                MonitorMap(displays: displays, windows: snapshot.windows).frame(height: 190)
                HStack(spacing: 12) {
                    DetailStat(value: "\(displays.count)", label: "Displays")
                    DetailStat(value: "\(snapshot.windows.count)", label: "Windows", action: { presentedContents = .windows })
                    DetailStat(value: "\(Set(snapshot.windows.map(\.bundleIdentifier)).count)", label: "Apps", action: { presentedContents = .apps })
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Windows by display").font(.headline)
                    ForEach(displays, id: \.identity.stableID) { display in
                        let count = snapshot.windows.filter { $0.sourceDisplayID == display.identity.stableID }.count
                        HStack {
                            Image(systemName: display.isPrimary ? "display.and.arrow.down" : "display").foregroundStyle(display.isPrimary ? Color.accentColor : Color.secondary)
                            Text(display.isPrimary ? "Main display" : "External display")
                            Text("\(Int(display.bounds.width)) × \(Int(display.bounds.height))").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(count) window\(count == 1 ? "" : "s")").fontWeight(.medium).monospacedDigit()
                        }.font(.subheadline).padding(.vertical, 8)
                        if display.identity.stableID != displays.last?.identity.stableID { Divider() }
                    }
                }.padding(14).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $presentedContents) { contents in
            SavedContentsView(snapshot: snapshot, contents: contents)
        }
    }
}

private struct DetailStat: View {
    let value: String; let label: String
    var action: (() -> Void)? = nil
    var body: some View {
        if let action {
            Button(action: action) { cardContents }
                .buttonStyle(.plain)
                .accessibilityHint("Show saved \(label.lowercased())")
        } else {
            cardContents
        }
    }

    private var cardContents: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private enum SavedContents: String, Identifiable {
    case windows, apps
    var id: String { rawValue }
}

private struct SavedContentsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let snapshot: LayoutSnapshot
    let contents: SavedContents

    private var currentSnapshot: LayoutSnapshot {
        model.snapshot(for: snapshot.configuration.fingerprint) ?? snapshot
    }

    private var appGroups: [(bundleIdentifier: String, windows: [WindowSnapshot])] {
        Dictionary(grouping: currentSnapshot.windows, by: \.bundleIdentifier)
            .map { (bundleIdentifier: $0.key, windows: $0.value.sorted(by: windowOrder)) }
            .sorted { applicationName(for: $0.bundleIdentifier).localizedCaseInsensitiveCompare(applicationName(for: $1.bundleIdentifier)) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(contents == .windows ? "Saved Windows" : "Saved Apps").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider()
            List {
                if contents == .windows {
                    ForEach(appGroups, id: \.bundleIdentifier) { group in
                        Section {
                            ForEach(group.windows) { window in
                                WindowRow(window: window, displayName: displayName(for: window)) {
                                    model.removeSavedWindows(ids: [window.id], from: currentSnapshot)
                                }
                            }
                        } header: {
                            ApplicationGroupHeader(
                                bundleIdentifier: group.bundleIdentifier,
                                name: applicationName(for: group.bundleIdentifier),
                                windowCount: group.windows.count,
                                deleteAction: {
                                    model.removeSavedWindows(ids: Set(group.windows.map(\.id)), from: currentSnapshot)
                                }
                            )
                        }
                    }
                } else {
                    ForEach(appGroups, id: \.bundleIdentifier) { group in
                        ApplicationGroupHeader(
                            bundleIdentifier: group.bundleIdentifier,
                            name: applicationName(for: group.bundleIdentifier),
                            windowCount: group.windows.count,
                            deleteAction: {
                                model.removeSavedWindows(ids: Set(group.windows.map(\.id)), from: currentSnapshot)
                            }
                        )
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 580, height: 500)
    }

    private func applicationName(for bundleIdentifier: String) -> String {
        NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleIdentifier })?.localizedName ?? bundleIdentifier
    }

    private func displayName(for window: WindowSnapshot) -> String {
        guard let display = currentSnapshot.configuration.displays.first(where: { $0.identity.stableID == window.sourceDisplayID }) else { return "Unknown display" }
        return display.isPrimary ? "Main display" : "External display"
    }

    private func windowOrder(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        let lhsName = applicationName(for: lhs.bundleIdentifier)
        let rhsName = applicationName(for: rhs.bundleIdentifier)
        if lhsName != rhsName { return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending }
        return lhs.key.normalizedTitle.localizedCaseInsensitiveCompare(rhs.key.normalizedTitle) == .orderedAscending
    }
}

private struct WindowRow: View {
    let window: WindowSnapshot
    let displayName: String
    let deleteAction: () -> Void

    private var title: String { window.key.normalizedTitle.isEmpty ? "Untitled window" : window.key.normalizedTitle }
    private var size: String { "\(Int((window.relativeFrame.width * 100).rounded()))% × \(Int((window.relativeFrame.height * 100).rounded()))% of display" }

    var body: some View {
        HStack(spacing: 10) {
            ApplicationIcon(bundleIdentifier: window.bundleIdentifier)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                HStack(spacing: 5) {
                    Text(displayName)
                    Text(size)
                    if window.wasMinimized { Text("Minimized") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(role: .destructive, action: deleteAction) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove this window from the saved layout")
            .accessibilityLabel("Remove \(title) from the saved layout")
        }
        .padding(.vertical, 3)
    }
}

private struct ApplicationGroupHeader: View {
    let bundleIdentifier: String
    let name: String
    let windowCount: Int
    var deleteAction: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ApplicationIcon(bundleIdentifier: bundleIdentifier)
            Text(name)
            Spacer()
            Text("\(windowCount) window\(windowCount == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
            if let deleteAction {
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Remove \(name) and its saved windows from this layout")
                .accessibilityLabel("Remove \(name) from the saved layout")
            }
        }
        .textCase(nil)
    }
}

private struct ApplicationIcon: View {
    let bundleIdentifier: String

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
    }
}

private struct MonitorMap: View {
    let displays: [DisplayDescriptor]; let windows: [WindowSnapshot]
    var body: some View {
        GeometryReader { proxy in
            let union = displayUnion
            let available = CGRect(x: 18, y: 18, width: proxy.size.width - 36, height: proxy.size.height - 36)
            let scale = min(available.width / max(union.width, 1), available.height / max(union.height, 1))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
                ForEach(displays, id: \.identity.stableID) { display in
                    let frame = scaledFrame(for: display.bounds, union: union, in: available, scale: scale)
                    MonitorTile(display: display, windowCount: windows.filter { $0.sourceDisplayID == display.identity.stableID }.count)
                        .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.7)))
        .accessibilityElement(children: .combine).accessibilityLabel("Graphical display arrangement with \(displays.count) displays")
    }
    private var displayUnion: CGRect { displays.map { $0.bounds.cgRect }.reduce(.null) { $0.union($1) } }
    private func scaledFrame(for bounds: RectValue, union: CGRect, in available: CGRect, scale: CGFloat) -> CGRect {
        let rect = bounds.cgRect
        return CGRect(x: available.minX + (rect.minX - union.minX) * scale, y: available.minY + (union.maxY - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale)
    }
}

private struct MonitorTile: View {
    let display: DisplayDescriptor; let windowCount: Int
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8).fill(display.isPrimary ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
            RoundedRectangle(cornerRadius: 8).strokeBorder(display.isPrimary ? Color.accentColor.opacity(0.8) : .secondary.opacity(0.65), lineWidth: display.isPrimary ? 2 : 1)
            if display.isPrimary { Rectangle().fill(Color.accentColor).frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 8)) }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(display.bounds.x)), \(Int(display.bounds.y))").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(display.bounds.width)) × \(Int(display.bounds.height))").font(.caption.weight(.semibold).monospacedDigit())
                Text("\(windowCount) window\(windowCount == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
            }.padding(8)
        }.minimumScaleFactor(0.6)
    }
}
