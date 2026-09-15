import SwiftUI

@main
struct WindowSaverApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        MenuBarExtra("Window Saver", systemImage: "rectangle.3.group") { MenuContent().environmentObject(model) }
            .menuBarExtraStyle(.menu)
        Settings { SettingsView().environmentObject(model) }
    }
}
