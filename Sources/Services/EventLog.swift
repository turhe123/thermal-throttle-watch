import Foundation

/// A period during which the Mac was throttling or above the user's temperature limit.
struct ThrottleEvent: Codable, Identifiable {
    enum Kind: String, Codable {
        case thermalState, overLimit
    }
    let id: UUID
    let kind: Kind
    let start: Date
    var end: Date?
    var detail: String

    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

/// Keeps the last 14 days of throttle events, persisted as JSON in Application Support.
@MainActor
final class EventLog: ObservableObject {
    @Published private(set) var events: [ThrottleEvent] = []
    private let retention: TimeInterval = 14 * 24 * 3600
    private let fileURL: URL?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let dir = base?.appendingPathComponent("ThermalThrottleWatch", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        fileURL = dir?.appendingPathComponent("events.json")
        load()
    }

    func begin(_ kind: ThrottleEvent.Kind, detail: String) -> UUID {
        let event = ThrottleEvent(id: UUID(), kind: kind, start: Date(), end: nil, detail: detail)
        events.insert(event, at: 0)
        save()
        return event.id
    }

    func end(_ id: UUID) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        events[index].end = Date()
        save()
    }

    func clear() {
        events.removeAll()
        save()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([ThrottleEvent].self, from: data) else { return }
        // Events still open from a previous run ended no later than the last write.
        let lastWrite = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        for i in loaded.indices where loaded[i].end == nil {
            loaded[i].end = max(lastWrite ?? loaded[i].start, loaded[i].start)
        }
        events = loaded
        save()
    }

    private func save() {
        let cutoff = Date().addingTimeInterval(-retention)
        events.removeAll { ($0.end ?? Date()) < cutoff }
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
