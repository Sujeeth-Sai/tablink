import Foundation
public struct Device: Identifiable, Equatable, Sendable {
    public let serial: String
    public let state: String
    public let model: String
    public var id: String { serial }
    public var isReady: Bool { state == "device" }
    public var isWireless: Bool { serial.contains(":") || serial.contains("_adb-tls") }
    public init(serial: String, state: String, model: String) { self.serial=serial; self.state=state; self.model=model }
    public static func parse(_ output: String) -> [Device] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2, !line.hasPrefix("List of"), !line.hasPrefix("*"),
                  ["device", "offline", "unauthorized", "recovery", "sideload", "no"].contains(parts[1]) else { return nil }
            let model = parts.first(where: { $0.hasPrefix("model:") }).map { String($0.dropFirst(6)).replacingOccurrences(of: "_", with: " ") } ?? parts[0]
            return Device(serial: parts[0], state: parts[1], model: model)
        }
    }
}
public struct Endpoint: Equatable {
    public let value: String
    public init(_ raw: String) throws {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = raw.lastIndex(of: ":"), let port = Int(raw[raw.index(after: colon)...]), (1...65535).contains(port) else { throw ValidationError.endpoint }
        let host = raw[..<colon]
        guard !host.isEmpty, host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:[]".contains($0)) }), !host.hasPrefix("-") else { throw ValidationError.endpoint }
        self.value = raw
    }
}
public enum ValidationError: Error, LocalizedError { case endpoint; public var errorDescription: String? { "Enter an address and port, for example 192.168.1.42:37123." } }
