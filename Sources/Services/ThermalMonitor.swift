import Foundation
import UserNotifications

/// Polls the system thermal state and SMC/battery temperatures, smooths readings, keeps
/// peaks and a 30-minute history of the hottest sensor, and feeds the `AlertEngine`.
@MainActor
final class ThermalMonitor: ObservableObject {
    /// One row in the popover: a sensor group's smoothed current value and peak since launch.
    struct Sensor: Identifiable {
        let kind: SensorKind
        var current: Double
        var peak: Double
        var id: SensorKind { kind }
    }

    /// One point of the hottest-sensor sparkline.
    struct Sample {
        let date: Date
        let value: Double
    }

    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    @Published private(set) var sensors: [Sensor] = []
    @Published private(set) var history: [Sample] = []
    @Published private(set) var smcAvailable: Bool
    @Published private(set) var notificationsDenied = false

    let events = EventLog()
    static let historyWindow: TimeInterval = 30 * 60

    private let smc = SMCReader()
    private lazy var alerts = AlertEngine(events: events)
    private var keys: [SensorKind: [String]] = [:]
    private var useBatteryRegistry = false
    private var recent: [SensorKind: [Double]] = [:]
    private var peaks: [SensorKind: Double] = [:]
    private var timer: Timer?
    private var stateObserver: NSObjectProtocol?
    private let smoothingWindow = 3
    private let plausible = 10.0...120.0

    var hottest: Double? { sensors.map(\.current).max() }

    init() {
        Prefs.registerDefaults()
        smcAvailable = smc.isOpen
        probeSensors()
        stateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        if UserDefaults.standard.bool(forKey: Prefs.notifications) { requestNotificationAccess() }
        refresh()
        restartTimer()
    }

    /// Re-creates the polling timer using the current refresh-interval setting.
    func restartTimer() {
        timer?.invalidate()
        let seconds = max(2, UserDefaults.standard.integer(forKey: Prefs.refreshInterval))
        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func requestNotificationAccess() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.notificationsDenied = !granted }
        }
    }

    /// Keeps only the SMC keys that answer with a plausible temperature on this Mac.
    private func probeSensors() {
        guard smc.isOpen else {
            useBatteryRegistry = SmartBattery.temperature().map(plausible.contains) ?? false
            return
        }
        for kind in SensorKind.allCases {
            let found = kind.smcKeys.filter { key in smc.readValue(key).map(plausible.contains) ?? false }
            if !found.isEmpty { keys[kind] = found }
        }
        if keys[.battery] == nil {
            useBatteryRegistry = SmartBattery.temperature().map(plausible.contains) ?? false
        }
    }

    private func refresh() {
        thermalState = ProcessInfo.processInfo.thermalState
        var updated: [Sensor] = []
        for kind in SensorKind.allCases {
            var readings = (keys[kind] ?? []).compactMap { smc.readValue($0) }.filter(plausible.contains)
            if kind == .battery, useBatteryRegistry, let battery = SmartBattery.temperature(), plausible.contains(battery) {
                readings.append(battery)
            }
            guard let raw = readings.max() else { continue }

            var window = recent[kind, default: []]
            window.append(raw)
            if window.count > smoothingWindow { window.removeFirst(window.count - smoothingWindow) }
            recent[kind] = window
            let smoothed = window.reduce(0, +) / Double(window.count)
            let peak = max(peaks[kind] ?? smoothed, smoothed)
            peaks[kind] = peak
            updated.append(Sensor(kind: kind, current: smoothed, peak: peak))
        }
        sensors = updated

        let now = Date()
        if let hottest {
            history.append(Sample(date: now, value: hottest))
        }
        history.removeAll { now.timeIntervalSince($0.date) > Self.historyWindow }
        alerts.evaluate(state: thermalState, hottest: hottest)
    }
}
