import AppKit
import ApplicationServices

protocol WindowAccessibilityProviding: Sendable {
    func isTrusted(prompt: Bool) -> Bool
    func captureWindows(in configuration: DisplayConfiguration, excludedBundleIDs: Set<String>) -> [WindowSnapshot]
    func captureWindows(for app: NSRunningApplication, in configuration: DisplayConfiguration) -> [WindowSnapshot]
    func captureFocusedWindow(for app: NSRunningApplication, in configuration: DisplayConfiguration) -> WindowSnapshot?
    func restore(_ snapshot: WindowSnapshot, in configuration: DisplayConfiguration) -> RestoreResult
}

final class WindowAccessibilityService: WindowAccessibilityProviding, @unchecked Sendable {
    func isTrusted(prompt: Bool = false) -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }
    func captureWindows(in configuration: DisplayConfiguration, excludedBundleIDs: Set<String>) -> [WindowSnapshot] {
        guard isTrusted() else { return [] }
        return NSWorkspace.shared.runningApplications.flatMap { app -> [WindowSnapshot] in
            guard let bundleID = app.bundleIdentifier, !excludedBundleIDs.contains(bundleID) else { return [] }
            return captureWindows(for: app, in: configuration)
        }
    }
    func captureWindows(for app: NSRunningApplication, in configuration: DisplayConfiguration) -> [WindowSnapshot] {
        guard isTrusted(), let bundleID = app.bundleIdentifier else { return [] }
        return appWindows(for: app).enumerated().compactMap { snapshot(for: $0.element, ordinal: $0.offset, bundleIdentifier: bundleID, configuration: configuration) }
    }
    func captureFocusedWindow(for app: NSRunningApplication, in configuration: DisplayConfiguration) -> WindowSnapshot? {
        guard isTrusted(), let bundleID = app.bundleIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value else { return nil }
        let windows = appWindows(for: app)
        let ordinal = windows.firstIndex { CFEqual($0, window) } ?? 0
        return snapshot(for: unsafeBitCast(window, to: AXUIElement.self), ordinal: ordinal, bundleIdentifier: bundleID, configuration: configuration)
    }
    func restore(_ snapshot: WindowSnapshot, in configuration: DisplayConfiguration) -> RestoreResult {
        var result = RestoreResult()
        guard isTrusted() else { result.failed = 1; return result }
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == snapshot.bundleIdentifier }) else { result.unmatched = 1; return result }
        let candidates = appWindows(for: app).filter(isStandard)
        let descriptors = candidates.map(descriptor(for:))
        let decision = WindowMatcher.select(snapshot.key, from: descriptors)
        guard case let .match(index) = decision else { if decision == .ambiguous { result.ambiguous = 1 } else { result.unmatched = 1 }; return result }
        let window = candidates[index]
        guard let display = configuration.displays.first(where: { $0.identity.stableID == snapshot.sourceDisplayID }) else { result.unmatched = 1; return result }
        let target = absolute(snapshot.relativeFrame.cgRect, in: display.bounds.cgRect)
        guard let current = frameValue(window)?.cgRect else { result.unsupported = 1; return result }
        if approximatelyEqual(current, target) { result.alreadyCorrect = 1; return result }
        guard setFrame(window, target) else { result.failed = 1; return result }
        result.moved = 1; return result
    }
    private func appWindows(for app: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
    private func snapshot(for window: AXUIElement, ordinal: Int, bundleIdentifier: String, configuration: DisplayConfiguration) -> WindowSnapshot? {
        guard isStandard(window), let frame = frameValue(window), let display = display(containing: frame.cgRect, configuration: configuration) else { return nil }
        let title = stringValue(window, attribute: "AXTitle") ?? ""
        let key = WindowKey(accessibilityIdentifier: stringValue(window, attribute: "AXIdentifier"), documentURL: stringValue(window, attribute: "AXDocument"), normalizedTitle: normalize(title), role: stringValue(window, attribute: "AXRole") ?? "", subrole: stringValue(window, attribute: "AXSubrole") ?? "", ordinal: ordinal)
        return WindowSnapshot(id: UUID(), bundleIdentifier: bundleIdentifier, key: key, sourceDisplayID: display.identity.stableID, relativeFrame: relative(frame.cgRect, to: display.bounds.cgRect), wasMinimized: boolValue(window, attribute: kAXMinimizedAttribute) ?? false)
    }
    private func isStandard(_ window: AXUIElement) -> Bool {
        guard stringValue(window, attribute: "AXRole") == "AXWindow" else { return false }
        var positionSettable = DarwinBoolean(false), sizeSettable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(window, "AXPosition" as CFString, &positionSettable) == .success && positionSettable.boolValue && AXUIElementIsAttributeSettable(window, "AXSize" as CFString, &sizeSettable) == .success && sizeSettable.boolValue
    }
    private func stringValue(_ element: AXUIElement, attribute: String) -> String? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }; return value as? String }
    private func boolValue(_ element: AXUIElement, attribute: String) -> Bool? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }; return value as? Bool }
    private func rectValue(_ element: AXUIElement, attribute: String) -> RectValue? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else { return nil }; var rect = CGRect.zero; guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgRect, &rect) else { return nil }; return RectValue(rect) }
    private func frameValue(_ window: AXUIElement) -> RectValue? { guard let position = pointValue(window), let size = sizeValue(window) else { return nil }; return RectValue(CGRect(origin: position, size: size)) }
    private func pointValue(_ element: AXUIElement) -> CGPoint? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, "AXPosition" as CFString, &value) == .success, let axValue = value else { return nil }; var point = CGPoint.zero; guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgPoint, &point) else { return nil }; return point }
    private func sizeValue(_ element: AXUIElement) -> CGSize? { var value: CFTypeRef?; guard AXUIElementCopyAttributeValue(element, "AXSize" as CFString, &value) == .success, let axValue = value else { return nil }; var size = CGSize.zero; guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgSize, &size) else { return nil }; return size }
    private func setFrame(_ window: AXUIElement, _ frame: CGRect) -> Bool { var point = frame.origin, size = frame.size; guard let p = AXValueCreate(.cgPoint, &point), let s = AXValueCreate(.cgSize, &size) else { return false }; return AXUIElementSetAttributeValue(window, "AXPosition" as CFString, p) == .success && AXUIElementSetAttributeValue(window, "AXSize" as CFString, s) == .success }
    private func display(containing frame: CGRect, configuration: DisplayConfiguration) -> DisplayDescriptor? { configuration.displays.max { intersection(frame, $0.bounds.cgRect) < intersection(frame, $1.bounds.cgRect) } }
    private func intersection(_ a: CGRect, _ b: CGRect) -> CGFloat { a.intersection(b).width * a.intersection(b).height }
    private func relative(_ frame: CGRect, to display: CGRect) -> RectValue { RectValue(CGRect(x: (frame.minX - display.minX) / display.width, y: (frame.minY - display.minY) / display.height, width: frame.width / display.width, height: frame.height / display.height)) }
    private func absolute(_ relative: CGRect, in display: CGRect) -> CGRect { CGRect(x: display.minX + relative.minX * display.width, y: display.minY + relative.minY * display.height, width: relative.width * display.width, height: relative.height * display.height) }
    private func normalize(_ title: String) -> String { title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
    private func descriptor(for window: AXUIElement) -> WindowMatchCandidate { WindowMatchCandidate(accessibilityIdentifier: stringValue(window, attribute: "AXIdentifier"), documentURL: stringValue(window, attribute: "AXDocument"), normalizedTitle: normalize(stringValue(window, attribute: "AXTitle") ?? ""), role: stringValue(window, attribute: "AXRole") ?? "", subrole: stringValue(window, attribute: "AXSubrole") ?? "") }
    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool { abs(a.minX - b.minX) <= 2 && abs(a.minY - b.minY) <= 2 && abs(a.width - b.width) <= 2 && abs(a.height - b.height) <= 2 }
}
