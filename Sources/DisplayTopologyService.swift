import AppKit
import CoreGraphics

protocol DisplayTopologyProviding: Sendable {
    func currentConfiguration() -> DisplayConfiguration
    func startObserving(_ handler: @escaping @Sendable () -> Void)
}

final class DisplayTopologyService: DisplayTopologyProviding, @unchecked Sendable {
    private var callback: (@Sendable () -> Void)?
    private var workItem: DispatchWorkItem?
    func currentConfiguration() -> DisplayConfiguration {
        let screens = NSScreen.screens
        let descriptors = screens.compactMap { screen -> DisplayDescriptor? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(number.uint32Value)
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id), serial = CGDisplaySerialNumber(id)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() as? UUID
            let stable = uuid?.uuidString ?? "\(vendor)-\(model)-\(serial)"
            return DisplayDescriptor(identity: DisplayIdentity(stableID: stable, vendor: vendor, model: model, serial: serial), bounds: RectValue(CGDisplayBounds(id)), scale: screen.backingScaleFactor, rotation: CGDisplayRotation(id), isPrimary: id == CGMainDisplayID())
        }.sorted { $0.identity.stableID < $1.identity.stableID }
        return DisplayConfiguration(schemaVersion: DisplayConfiguration.schemaVersion, displays: descriptors)
    }
    func startObserving(_ handler: @escaping @Sendable () -> Void) {
        callback = handler
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            let service = Unmanaged<DisplayTopologyService>.fromOpaque(userInfo!).takeUnretainedValue()
            service.scheduleCallback()
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    private func scheduleCallback() {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.callback?() }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }
}
