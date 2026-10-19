import SwiftUI

/// App entry point: a menu-bar-only app with a window-style popover and a Settings scene.
@main
struct ThermalThrottleWatchApp: App {
    @StateObject private var monitor = ThermalMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(monitor)
        } label: {
            MenuBarLabel().environmentObject(monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environmentObject(monitor)
        }
    }
}
