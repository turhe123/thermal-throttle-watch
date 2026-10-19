import Foundation
import UserNotifications

/// Decides when to warn and when to announce recovery, applying 3 °C hysteresis and a
/// five-minute per-condition cooldown, and records each episode in the `EventLog`.
@MainActor
final class AlertEngine {
    private let events: EventLog
    private let hysteresis = 3.0
    private let cooldown: TimeInterval = 5 * 60
    private var openEvents: [ThrottleEvent.Kind: UUID] = [:]
    private var lastSent: [String: Date] = [:]

    init(events: EventLog) {
        self.events = events
    }

    func evaluate(state: ProcessInfo.ThermalState, hottest: Double?) {
        let defaults = UserDefaults.standard
        let threshold = defaults.double(forKey: Prefs.threshold)
        let unit = defaults.string(forKey: Prefs.unit) ?? "C"

        let throttling = state.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        update(.thermalState, active: throttling, recovered: !throttling,
               detail: "Thermal state \(state.title)",
               enterTitle: "Your Mac is throttling",
               enterBody: "Thermal state is \(state.title). \(state.detail)",
               exitBody: "Thermal state is back to \(state.title).")

        if let hottest {
            let reading = Temperature.string(hottest, unit: unit)
            let limit = Temperature.string(threshold, unit: unit)
            update(.overLimit, active: hottest >= threshold, recovered: hottest < threshold - hysteresis,
                   detail: "Hottest sensor \(reading)",
                   enterTitle: "Temperature above \(limit)",
                   enterBody: "The hottest sensor reads \(reading).",
                   exitBody: "The hottest sensor has cooled to \(reading).")
        }
    }

    private func update(_ kind: ThrottleEvent.Kind, active: Bool, recovered: Bool, detail: String,
                        enterTitle: String, enterBody: String, exitBody: String) {
        if active, openEvents[kind] == nil {
            openEvents[kind] = events.begin(kind, detail: detail)
            notify(key: "\(kind.rawValue).enter", title: enterTitle, body: enterBody)
        } else if recovered, let id = openEvents[kind] {
            events.end(id)
            openEvents[kind] = nil
            notify(key: "\(kind.rawValue).exit", title: "Your Mac has cooled down", body: exitBody)
        }
    }

    private func notify(key: String, title: String, body: String) {
        guard UserDefaults.standard.bool(forKey: Prefs.notifications) else { return }
        if let last = lastSent[key], Date().timeIntervalSince(last) < cooldown { return }
        lastSent[key] = Date()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

/// Lets notifications appear as banners even though the menu bar app is always "active".
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
