import AppKit
import ServiceManagement
import SwiftUI

/// Preferences: unit, alert threshold, notifications, menu bar number, refresh rate, launch at login.
struct SettingsView: View {
    @EnvironmentObject private var monitor: ThermalMonitor
    @AppStorage(Prefs.unit) private var unit = "C"
    @AppStorage(Prefs.threshold) private var threshold = 90.0
    @AppStorage(Prefs.notifications) private var notifications = true
    @AppStorage(Prefs.showNumber) private var showNumber = true
    @AppStorage(Prefs.refreshInterval) private var refreshInterval = 5
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Display") {
                Picker("Temperature unit", selection: $unit) {
                    Text("Celsius (°C)").tag("C")
                    Text("Fahrenheit (°F)").tag("F")
                }
                Toggle("Show hottest temperature in menu bar", isOn: $showNumber)
                Picker("Refresh every", selection: $refreshInterval) {
                    ForEach([2, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) }
                }
            }
            Section("Alerts") {
                Toggle("Notify on Serious thermal state or high temperature", isOn: $notifications)
                VStack(alignment: .leading) {
                    Text("Alert threshold: \(Temperature.string(threshold, unit: unit))")
                    Slider(value: $threshold, in: 60...105, step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text(Temperature.string(60, unit: unit))
                    } maximumValueLabel: {
                        Text(Temperature.string(105, unit: unit))
                    }
                }
                .disabled(!notifications)
                if notifications && monitor.notificationsDenied {
                    HStack {
                        Text("Notifications are turned off for ThermalThrottleWatch in System Settings.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                Button("Support / Donate ❤️") {
                    if let url = URL(string: "https://ko-fi.com/leodavidai") { NSWorkspace.shared.open(url) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: refreshInterval) { monitor.restartTimer() }
        .onChange(of: notifications) { _, enabled in
            if enabled { monitor.requestNotificationAccess() }
        }
        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
        .onAppear { if notifications { monitor.requestNotificationAccess() } }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}
