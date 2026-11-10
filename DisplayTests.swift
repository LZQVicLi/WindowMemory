import Foundation

private final class TestDDCBus: DDCTransport {
    private(set) var requests: [[UInt8]] = []
    var replies: [[UInt8]?]
    init(_ replies: [[UInt8]?]) { self.replies = replies }
    func transfer(_ request: [UInt8], replyLength: Int, wait: UInt32) -> [UInt8]? {
        requests.append(request)
        return replies.isEmpty ? nil : replies.removeFirst()
    }
}

func runDisplayTests() -> Int {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        count += 1
        print("PASS: \(name)")
    }
    func reply(_ bytes: [UInt8]) -> [UInt8] {
        let frame: [UInt8] = [0x6E, 0x80 | UInt8(bytes.count)] + bytes
        return frame + [frame.reduce(0x50, ^)]
    }
    let brightnessReply = reply([0x02, 0x00, 0x10, 0x00, 0x01, 0xFF, 0x01, 0x00])
    let parsed = DDCWire.payload(brightnessReply + [0, 0]).flatMap { DDCWire.reading($0, code: 0x10) }
    check(parsed == DDCReading(current: 256, maximum: 511), "DDC read uses big-endian 16-bit values and declared length")

    var corrupted = brightnessReply
    corrupted[corrupted.count - 1] ^= 1
    check(DDCWire.payload(corrupted) == nil && DDCWire.payload(Array(brightnessReply.dropLast())) == nil,
          "invalid checksum and truncated DDC replies cannot enable controls")
    let wrongFeature = reply([0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x20])
    let bus = TestDDCBus([wrongFeature, brightnessReply, []])
    let monitor = DDCMonitor(bus: bus)
    check(monitor.get(0x10) == parsed && bus.requests == [[0x51,0x82,0x01,0x10,0xAC], [0x51,0x82,0x01,0x10,0xAC]],
          "a stale feature reply is retried with the correct Get VCP frame")
    check(monitor.set(0x10, value: 0x0100) && bus.requests.last == [0x51,0x84,0x03,0x10,0x01,0x00,0xA9],
          "Set VCP frame encodes the high and low bytes and checksum")

    let capabilitiesText = "(prot(monitor)vcp(10 12 14(01 05 0B) 60(0F1112) D6(01 04) FD)mccs_ver(2.2))"
    let bytes = Array(capabilitiesText.utf8)
    let segments = stride(from: 0, to: bytes.count, by: 26).map { offset in
        reply([0xE3, 0, UInt8(offset)] + Array(bytes[offset..<min(offset+26,bytes.count)]))
    }
    let capsBus = TestDDCBus(segments.map { Optional($0) } + [reply([0xE3, 0, UInt8(bytes.count)])])
    let caps = DDCMonitor(bus: capsBus).capabilities()
    check(caps?.features[0x60] == [15,17,18] && caps?.features[0x14] == [1,5,11]
          && caps?.features[0x0F] == nil && caps?.version == "2.2",
          "chunked capabilities keep input values separate from feature IDs")
    check(DDCCapabilities.parse("(vcp(60(0F 11)") == nil &&
          DDCMonitor(bus: TestDDCBus([reply([0xE3, 0, 1, 65])])).capabilities() == nil,
          "truncated capability blocks and mismatched offsets are rejected")
    let cancelled = TestDDCBus([segments[0]])
    check(DDCMonitor(bus: cancelled).capabilities(isCancelled: { true }) == nil && cancelled.requests.isEmpty,
          "cancelled scans do not issue further DDC requests")

    let input = MonitorAdjustment(code: .input, reading: .init(current: 15, maximum: 3), advertised: [15,17])
    let unknownInputs = MonitorAdjustment(code: .input, reading: .init(current: 15, maximum: 3), advertised: [])
    check(input.accepts(17) && !input.accepts(18) && unknownInputs.style == .readOnly && !unknownInputs.accepts(17),
          "input switching is limited to ports advertised by the monitor")
    let inconsistent = MonitorAdjustment(code: .sharpness, reading: .init(current: 50, maximum: 4), advertised: [])
    let valid = MonitorAdjustment(code: .brightness, reading: .init(current: 80, maximum: 100), advertised: [])
    check(inconsistent.style == .readOnly && !inconsistent.accepts(4) && valid.accepts(100) && !valid.accepts(101),
          "inconsistent firmware ranges stay read-only and normal ranges reject overflow")
    let mute = MonitorAdjustment(code: .mute, reading: .init(current: 0x0102, maximum: 2), advertised: [1,2])
    check(mute.style == .readOnly && !mute.accepts(1), "ambiguous mute encodings cannot blank the screen")
    return count
}
