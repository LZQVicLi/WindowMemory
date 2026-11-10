import Foundation

/// DDC/CI framing is independent of the hardware bus. All byte counts and
/// checksums are validated before a monitor reply can enable an editable control.
enum DDCWire {
    static func request(_ payload: [UInt8]) -> [UInt8] {
        let bytes: [UInt8] = [0x51, 0x80 | UInt8(payload.count)] + payload
        return bytes + [bytes.reduce(0x6E, ^)]
    }

    static func payload(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 3, bytes[0] == 0x6E, bytes[1] & 0x80 != 0 else { return nil }
        let end = Int(bytes[1] & 0x7F) + 2
        guard bytes.count > end, bytes[0...end].reduce(0x50, ^) == 0 else { return nil }
        return Array(bytes[2..<end])
    }

    static func reading(_ payload: [UInt8], code: UInt8) -> DDCReading? {
        guard payload.count == 8, payload[0] == 0x02, payload[1] == 0, payload[2] == code else { return nil }
        return DDCReading(current: word(payload[6], payload[7]), maximum: word(payload[4], payload[5]))
    }

    static func capabilityChunk(_ payload: [UInt8], offset: UInt16) -> [UInt8]? {
        guard payload.count >= 3, payload[0] == 0xE3, word(payload[1], payload[2]) == offset else { return nil }
        return Array(payload.dropFirst(3))
    }

    private static func word(_ hi: UInt8, _ lo: UInt8) -> UInt16 { UInt16(hi) << 8 | UInt16(lo) }
}

struct DDCReading: Equatable {
    let current: UInt16
    let maximum: UInt16
}

struct DDCCapabilities: Equatable {
    let features: [UInt8: [UInt16]]
    let version: String?

    static func parse(_ string: String) -> DDCCapabilities? {
        // Extract the balanced VCP block, keeping its nested per-feature values
        // separate from feature IDs (for example 60(0F 11)).
        guard let start = string.range(of: #"\bvcp\s*\("#, options: [.regularExpression, .caseInsensitive])?.upperBound else { return nil }
        var depth = 1, end = start
        while end < string.endIndex {
            if string[end] == "(" { depth += 1 }
            if string[end] == ")" { depth -= 1 }
            if depth == 0 { break }
            end = string.index(after: end)
        }
        guard depth == 0 else { return nil }
        // Tokenize the punctuation too. Accept commonly reported concatenated
        // two-digit hexadecimal values without treating them as arbitrary words.
        let vcp = String(string[start..<end]).replacingOccurrences(of: "(", with: " ( ").replacingOccurrences(of: ")", with: " ) ")
        let fields = vcp.split(whereSeparator: \.isWhitespace)
        func hexBytes(_ token: Substring) -> [UInt8] {
            let bytes = Array(token.utf8)
            guard bytes.count >= 2, bytes.count % 2 == 0 else { return [] }
            let result = stride(from: 0, to: bytes.count, by: 2).compactMap {
                UInt8(String(decoding: bytes[$0..<$0+2], as: UTF8.self), radix: 16)
            }
            return result.count * 2 == bytes.count ? result : []
        }
        var features: [UInt8: [UInt16]] = [:], pending: UInt8?, values = [UInt16]()
        var inValues = false
        for field in fields {
            if field == "(" {
                guard !inValues, pending != nil else { return nil }
                values = []; inValues = true
            } else if field == ")" {
                guard inValues, let code = pending else { return nil }
                features[code] = Array(Set((features[code] ?? []) + values)).sorted()
                inValues = false; pending = nil
            } else if inValues {
                values += hexBytes(field).map(UInt16.init)
            } else {
                for code in hexBytes(field) {
                    if features[code] == nil { features[code] = [] }
                    pending = code
                }
            }
        }
        guard !inValues, !features.isEmpty else { return nil }
        let version = string.range(of: #"\bmccs_ver\s*\([0-9.]+\)"#, options: [.regularExpression, .caseInsensitive])
            .flatMap { string[$0].split(separator: "(").last?.dropLast() }.map(String.init)
        return DDCCapabilities(features: features, version: version)
    }
}

protocol DDCTransport: AnyObject {
    /// replyLength == 0 is a set operation. The caller serializes all traffic.
    func transfer(_ request: [UInt8], replyLength: Int, wait: UInt32) -> [UInt8]?
}

struct DDCMonitor {
    let bus: DDCTransport

    func get(_ code: UInt8) -> DDCReading? {
        let request = DDCWire.request([0x01, code])
        for _ in 0..<2 {
            guard let reply = bus.transfer(request, replyLength: 11, wait: 50_000),
                  let payload = DDCWire.payload(reply) else { continue }
            if payload.count == 8, payload[0] == 0x02, payload[2] == code {
                return DDCWire.reading(payload, code: code)
            }
        }
        return nil
    }

    func set(_ code: UInt8, value: UInt16) -> Bool {
        bus.transfer(DDCWire.request([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]),
                     replyLength: 0, wait: 50_000) != nil
    }

    func capabilities(isCancelled: () -> Bool = { false }) -> DDCCapabilities? {
        var bytes = [UInt8]()
        // One broken firmware should never keep the screen list spinning.
        for _ in 0..<48 {
            guard !isCancelled() else { return nil }
            let offset = UInt16(bytes.count)
            let packet = DDCWire.request([0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
            guard let reply = bus.transfer(packet, replyLength: 38, wait: 55_000),
                  let payload = DDCWire.payload(reply),
                  let chunk = DDCWire.capabilityChunk(payload, offset: offset) else { return nil }
            if let zero = chunk.firstIndex(of: 0) { bytes += chunk[..<zero]; break }
            if chunk.isEmpty { break }
            bytes += chunk
        }
        return DDCCapabilities.parse(String(decoding: bytes, as: UTF8.self))
    }
}
