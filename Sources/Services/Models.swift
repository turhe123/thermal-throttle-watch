import AppKit
import SwiftUI

/// A group of physical sensors shown as one row in the popover (the hottest key in the group wins).
enum SensorKind: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, ssd, battery, ambient
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .ssd: return "SSD"
        case .battery: return "Battery"
        case .ambient: return "Ambient / Palm Rest"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cube.transparent"
        case .memory: return "memorychip"
        case .ssd: return "internaldrive"
        case .battery: return "battery.75percent"
        case .ambient: return "wind"
        }
    }

    /// Known SMC temperature keys for Intel and Apple Silicon (M1–M4). Probed at startup;
    /// only keys that return plausible values are kept.
    var smcKeys: [String] {
        switch self {
        case .cpu:
            return ["TC0P", "TC0D", "TC0E", "TC0F", "TCXC",                          // Intel
                    "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0T",  // M1
                    "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h", "Tp1t", "Tp1p", "Tp1l",  // M1/M2
                    "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B",  // M3
                    "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
                    "Tp0V", "Tp0Y", "Tp0e"]                                           // M4
        case .gpu:
            return ["TG0P", "TG0D", "TG0F", "Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0f", "Tg0j",
                    "Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
        case .memory: return ["TM0P", "TM0S", "Tm02", "Tm06", "Tm08", "Tm09"]
        case .ssd: return ["TH0P", "TH0a", "TH0b", "TH0x", "TH0A"]
        case .battery: return ["TB0T", "TB1T", "TB2T"]
        case .ambient: return ["TA0P", "TA0V", "Ts0P", "Ts0S", "Ts1P"]
        }
    }
}

/// Settings keys and defaults shared by `@AppStorage` and the background monitor.
enum Prefs {
    static let unit = "unit"                       // "C" or "F"
    static let threshold = "alertThreshold"        // °C, 60...105
    static let notifications = "notificationsEnabled"
    static let showNumber = "showNumberInMenuBar"
    static let refreshInterval = "refreshInterval" // seconds: 2, 5 or 10

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            unit: "C", threshold: 90.0, notifications: true, showNumber: true, refreshInterval: 5
        ])
    }
}

/// Formats Celsius readings in the user's preferred unit.
enum Temperature {
    static func string(_ celsius: Double, unit: String) -> String {
        unit == "F" ? String(format: "%.0f°F", celsius * 9 / 5 + 32) : String(format: "%.0f°C", celsius)
    }
}

extension ProcessInfo.ThermalState {
    var title: String {
        switch self {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var detail: String {
        switch self {
        case .nominal: return "Running cool, no throttling."
        case .fair: return "Slightly warm; fans may spin up."
        case .serious: return "Under thermal stress — performance is being reduced."
        case .critical: return "Very hot — heavy throttling. Let your Mac cool down."
        @unknown default: return "The system reported an unknown state."
        }
    }

    var nsColor: NSColor {
        switch self {
        case .nominal: return .systemGreen
        case .fair: return .systemYellow
        case .serious: return .systemOrange
        case .critical: return .systemRed
        @unknown default: return .systemGray
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}
