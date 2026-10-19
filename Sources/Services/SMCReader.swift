import Foundation
import IOKit

/// Read-only client for the AppleSMC IOKit service. Reads four-character keys and decodes
/// float and fixed-point temperature values. Every call checks return codes and sizes so
/// unknown keys on new chips simply return `nil`.
final class SMCReader {
    private var connection: io_connect_t = 0
    private(set) var isOpen = false
    private var keyInfoCache: [String: (size: Int, type: String)] = [:]

    // Byte layout of the kernel's SMCKeyData_t (80 bytes), addressed by offset to avoid
    // relying on Swift struct layout matching C padding.
    private static let structSize = 80
    private enum Offset {
        static let key = 0, dataSize = 28, dataType = 32, result = 40, command = 42, bytes = 48
    }
    private enum Command { static let readKey: UInt8 = 5, getKeyInfo: UInt8 = 9 }
    private static let handleEventSelector: UInt32 = 2

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        isOpen = IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess
    }

    deinit {
        if isOpen { IOServiceClose(connection) }
    }

    /// Reads a key and returns its value in °C, or `nil` if missing, unsupported or undecodable.
    func readValue(_ key: String) -> Double? {
        guard isOpen, let code = Self.fourCC(key) else { return nil }
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put(code, into: &input, at: Offset.key)

        let info: (size: Int, type: String)
        if let cached = keyInfoCache[key] {
            info = cached
        } else {
            input[Offset.command] = Command.getKeyInfo
            guard let out = call(input) else { return nil }
            info = (Int(Self.get(out, at: Offset.dataSize)), Self.string(from: Self.get(out, at: Offset.dataType)))
            keyInfoCache[key] = info
        }
        guard info.size > 0, info.size <= 32 else { return nil }

        Self.put(UInt32(info.size), into: &input, at: Offset.dataSize)
        input[Offset.command] = Command.readKey
        guard let out = call(input) else { return nil }
        let bytes = Array(out[Offset.bytes ..< Offset.bytes + info.size])
        guard let value = Self.decode(bytes, type: info.type), value.isFinite else { return nil }
        return value
    }

    private func call(_ input: [UInt8]) -> [UInt8]? {
        var input = input
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outSize = Self.structSize
        let conn = connection
        let result = input.withUnsafeMutableBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(conn, Self.handleEventSelector,
                                          inPtr.baseAddress, Self.structSize,
                                          outPtr.baseAddress, &outSize)
            }
        }
        guard result == kIOReturnSuccess, outSize == Self.structSize, output[Offset.result] == 0 else { return nil }
        return output
    }

    /// Decodes `flt `, `spXY` / `fpXY` fixed-point (Y = fraction bits, hex) and small unsigned ints.
    private static func decode(_ bytes: [UInt8], type: String) -> Double? {
        let chars = Array(type)
        if type == "flt ", bytes.count == 4 {
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        }
        if chars.count == 4, bytes.count == 2, type.hasPrefix("sp") || type.hasPrefix("fp"),
           let fraction = Int(String(chars[3]), radix: 16) {
            let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
            let scale = Double(1 << fraction)
            return type.hasPrefix("sp") ? Double(Int16(bitPattern: raw)) / scale : Double(raw) / scale
        }
        if type == "ui8 ", bytes.count == 1 { return Double(bytes[0]) }
        if type == "ui16", bytes.count == 2 { return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) }
        return nil
    }

    private static func fourCC(_ key: String) -> UInt32? {
        let utf8 = Array(key.utf8)
        guard utf8.count == 4 else { return nil }
        return utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func put(_ value: UInt32, into buffer: inout [UInt8], at offset: Int) {
        for i in 0..<4 { buffer[offset + i] = UInt8((value >> UInt32(8 * i)) & 0xFF) }
    }

    private static func get(_ buffer: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(buffer[offset + $1]) << UInt32(8 * $1) }
    }
}

/// Reads the battery temperature from the AppleSmartBattery registry entry (a second source).
enum SmartBattery {
    static func temperature() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0),
              let raw = prop.takeRetainedValue() as? NSNumber else { return nil }
        return raw.doubleValue / 100.0 // reported in hundredths of a degree Celsius
    }
}
