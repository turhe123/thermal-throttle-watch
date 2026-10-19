import AppKit
import SwiftUI

/// The menu bar popover: thermal state header, sensor list, sparkline, event log and footer.
struct ContentView: View {
    @EnvironmentObject private var monitor: ThermalMonitor
    @AppStorage(Prefs.unit) private var unit = "C"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !monitor.smcAvailable {
                Label("Sensor access is unavailable, so only the system thermal state is shown. SMC reads need a non-sandboxed build.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            Divider()
            sensorList
            if monitor.history.count > 1 {
                Divider()
                trend
            }
            Divider()
            EventsSection(events: monitor.events)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 330)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle().fill(monitor.thermalState.color).frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Thermal state: \(monitor.thermalState.title)").font(.headline)
                Text(monitor.thermalState.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var sensorList: some View {
        if monitor.sensors.isEmpty {
            Text("Only the system thermal state is available on this Mac. It is currently \(monitor.thermalState.title).")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Sensor"); Text("Now").gridColumnAlignment(.trailing); Text("Max").gridColumnAlignment(.trailing)
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(monitor.sensors) { sensor in
                    GridRow {
                        Label(sensor.kind.title, systemImage: sensor.kind.symbol)
                        Text(Temperature.string(sensor.current, unit: unit)).monospacedDigit()
                        Text(Temperature.string(sensor.peak, unit: unit)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trend: some View {
        let values = monitor.history.map(\.value)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Hottest sensor · last 30 min").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let low = values.min(), let high = values.max() {
                    Text("\(Temperature.string(low, unit: unit)) – \(Temperature.string(high, unit: unit))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            Sparkline(samples: monitor.history, window: ThermalMonitor.historyWindow)
                .stroke(monitor.thermalState.color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                .frame(height: 44)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
        }
    }

    private var footer: some View {
        HStack {
            Button("Support / Donate ❤️") {
                if let url = URL(string: "https://ko-fi.com/leodavidai") { NSWorkspace.shared.open(url) }
            }
            Spacer()
            SettingsLink { Text("Settings…") }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}

/// Lists recent throttle events (newest first) with a Clear button.
private struct EventsSection: View {
    @ObservedObject var events: EventLog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Throttle events (14 days)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { events.clear() }
                    .controlSize(.small)
                    .disabled(events.events.isEmpty)
            }
            if events.events.isEmpty {
                Text("No events recorded.").font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events.events) { event in
                            HStack {
                                Image(systemName: event.kind == .thermalState ? "flame" : "thermometer.high")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(event.start.formatted(date: .abbreviated, time: .shortened))
                                    Text(event.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Self.durationText(event)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
    }

    private static func durationText(_ event: ThrottleEvent) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        let text = formatter.string(from: max(event.duration, 1)) ?? "—"
        return event.end == nil ? "\(text) (ongoing)" : text
    }
}

/// A line chart of the hottest-sensor history, drawn with a SwiftUI `Path` over a fixed time window.
struct Sparkline: Shape {
    let samples: [ThermalMonitor.Sample]
    let window: TimeInterval

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let last = samples.last?.date,
              let low = samples.map(\.value).min(),
              let high = samples.map(\.value).max() else { return path }
        let span = max(high - low, 2)
        let base = low - (span - (high - low)) / 2
        for (index, sample) in samples.enumerated() {
            let x = rect.maxX - CGFloat(last.timeIntervalSince(sample.date) / window) * rect.width
            let y = rect.maxY - CGFloat((sample.value - base) / span) * (rect.height - 4) - 2
            let point = CGPoint(x: x, y: y)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The menu bar label: a thermometer tinted by thermal state plus the optional hottest reading.
struct MenuBarLabel: View {
    @EnvironmentObject private var monitor: ThermalMonitor
    @AppStorage(Prefs.showNumber) private var showNumber = true
    @AppStorage(Prefs.unit) private var unit = "C"

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: Self.icon(color: monitor.thermalState.nsColor))
            if showNumber, let hottest = monitor.hottest {
                Text(Temperature.string(hottest, unit: unit))
            }
        }
        .accessibilityLabel("Thermal state \(monitor.thermalState.title)")
    }

    private static func icon(color: NSColor) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "Thermal state")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
