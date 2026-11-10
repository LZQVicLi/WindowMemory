import AppKit
import CoreGraphics
import IOKit
import IOKit.i2c

struct ConnectedDisplay: Identifiable, Equatable {
    let number: CGDirectDisplayID
    let uuid: String?
    let name: String
    let builtIn: Bool
    let primary: Bool
    let width: Int
    let height: Int
    let refresh: Double
    let rotation: Int
    let mirrored: Bool

    var id: String { "\(number):\(uuid ?? "-")" }

    func isStillConnected() -> Bool {
        guard let uuid, CGDisplayIsOnline(number) != 0 else { return false }
        return Self.identity(number) == uuid
    }

    private static func identity(_ display: CGDirectDisplayID) -> String? {
        CGDisplayCreateUUIDFromDisplayID(display).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }

    static func online() -> [ConnectedDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var numbers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &numbers, &count) == .success else { return [] }
        let names = Dictionary(NSScreen.screens.compactMap { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { ($0.uint32Value, screen.localizedName) }
        }, uniquingKeysWith: { first, _ in first })
        return numbers.prefix(Int(count)).map { display in
            let mode = CGDisplayCopyDisplayMode(display)
            let builtIn = CGDisplayIsBuiltin(display) != 0
            let name = names[display] ?? DisplaySymbols.info(display)?["DisplayProductName"].flatMap { value in
                (value as? [String: String])?["en_US"] ?? (value as? [String: String])?.values.sorted().first
            } ?? (builtIn ? L("内建显示器") : L("外接显示器 \(display)"))
            return ConnectedDisplay(number: display, uuid: identity(display), name: name, builtIn: builtIn,
                primary: display == CGMainDisplayID(), width: mode?.width ?? CGDisplayPixelsWide(display),
                height: mode?.height ?? CGDisplayPixelsHigh(display), refresh: mode?.refreshRate ?? 0,
                rotation: Int(CGDisplayRotation(display).rounded()), mirrored: CGDisplayIsInMirrorSet(display) != 0)
        }.sorted { lhs, rhs in lhs.primary == rhs.primary ? lhs.number < rhs.number : lhs.primary }
    }
}

// Optional private symbols are resolved dynamically. If an OS build removes
// them, the app still opens and macOS Display Settings remain available.
private enum DisplaySymbols {
    static func symbol<T>(_ library: UnsafeMutableRawPointer?, _ name: String, _ type: T.Type) -> T? {
        guard let library, let address = dlsym(library, name) else { return nil }
        return unsafeBitCast(address, to: type)
    }

    static let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
    static let core = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL)
    static let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    static let brightness = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)

    typealias Info = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    typealias Service = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<io_service_t>) -> Void
    typealias CreateAV = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias I2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let createInfo = symbol(core, "CoreDisplay_DisplayCreateInfoDictionary", Info.self)
    static let serviceForDisplay = symbol(sky, "CGSServiceForDisplayNumber", Service.self)
    static let createAV = symbol(io, "IOAVServiceCreateWithService", CreateAV.self)
    static let readAV = symbol(io, "IOAVServiceReadI2C", I2C.self)
    static let writeAV = symbol(io, "IOAVServiceWriteI2C", I2C.self)
    static let getBrightness = symbol(brightness, "DisplayServicesGetBrightness", GetBrightness.self)
    static let setBrightness = symbol(brightness, "DisplayServicesSetBrightness", SetBrightness.self)

    static func info(_ id: CGDirectDisplayID) -> [String: Any]? {
        createInfo?(id)?.takeRetainedValue() as? [String: Any]
    }
    static func framebuffer(_ id: CGDirectDisplayID) -> io_service_t? {
        guard let path = info(id)?["IODisplayLocation"] as? String else { return nil }
        let entry = IORegistryEntryCopyFromPath(kIOMainPortDefault, path as CFString)
        return entry == 0 ? nil : entry
    }
}

#if arch(arm64)
private final class AVDisplayBus: DDCTransport {
    private let av: CFTypeRef
    private let chip: UInt32
    private let read: DisplaySymbols.I2C
    private let write: DisplaySymbols.I2C

    init?(_ display: ConnectedDisplay) {
        guard let create = DisplaySymbols.createAV, let read = DisplaySymbols.readAV, let write = DisplaySymbols.writeAV,
              let framebuffer = DisplaySymbols.framebuffer(display.number) else { return nil }
        defer { IOObjectRelease(framebuffer) }
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(framebuffer, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(parent) }
        // Framebuffers under dispextN can have their proxy under the sibling
        // dcpextN. Pair these by controller, never by global display order.
        let controller = Self.pairedController(parent)
        defer { if let controller { IOObjectRelease(controller) } }
        // Refuse ambiguous mappings rather than controlling the wrong monitor.
        var iter: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(controller ?? parent, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var candidate: CFTypeRef?
        var chip: UInt32 = 0x37
        while case let entry = IOIteratorNext(iter), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IOObjectConformsTo(entry, "DCPAVServiceProxy") != 0,
                  IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String == "External" else { continue }
            guard candidate == nil, let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { return nil }
            candidate = service
            var provider: io_registry_entry_t = 0
            if IORegistryEntryGetParentEntry(entry, kIOServicePlane, &provider) == KERN_SUCCESS {
                defer { IOObjectRelease(provider) }
                let type = IORegistryEntryCreateCFProperty(provider, "EPICProviderClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                if type == "AppleDCPMCDP29XX" { chip = 0xB7 }
            }
        }
        guard let candidate else { return nil }
        self.av = candidate; self.chip = chip; self.read = read; self.write = write
    }

    private static func pairedController(_ parent: io_registry_entry_t) -> io_registry_entry_t? {
        func name(_ entry: io_registry_entry_t) -> String {
            var bytes = [CChar](repeating: 0, count: MemoryLayout<io_name_t>.size)
            return IORegistryEntryGetName(entry, &bytes) == KERN_SUCCESS ? String(cString: bytes) : ""
        }
        let component = name(parent)
        guard component.hasPrefix("dispext"), let index = UInt16(component.dropFirst(7)) else { return nil }
        var root: io_registry_entry_t = 0, iterator: io_iterator_t = 0
        guard IORegistryEntryGetParentEntry(parent, kIOServicePlane, &root) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(root) }
        guard IORegistryEntryGetChildIterator(root, kIOServicePlane, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if name(entry) == "dcpext\(index)" { return entry }
            IOObjectRelease(entry)
        }
        return nil
    }

    func transfer(_ request: [UInt8], replyLength: Int, wait: UInt32) -> [UInt8]? {
        var frame = Array(request.dropFirst())
        let length = UInt32(frame.count)
        let result = frame.withUnsafeMutableBytes { write(av, chip, UInt32(request[0]), $0.baseAddress!, length) }
        guard result == KERN_SUCCESS else { return nil }
        usleep(wait)
        guard replyLength > 0 else { return [] }
        var reply = [UInt8](repeating: 0, count: replyLength)
        let status = reply.withUnsafeMutableBytes { read(av, chip, 0, $0.baseAddress!, UInt32(replyLength)) }
        return status == KERN_SUCCESS ? reply : nil
    }
}
#elseif arch(x86_64)
private final class IntelDisplayBus: DDCTransport {
    private let framebuffer: io_service_t
    private let busCount: UInt32
    private var workingBus: UInt32?

    init?(_ display: ConnectedDisplay) {
        var candidate: io_service_t = 0
        if let exact = DisplaySymbols.framebuffer(display.number) {
            var count: IOItemCount = 0
            if IOFBGetI2CInterfaceCount(exact, &count) == KERN_SUCCESS, count > 0 { candidate = exact }
            else { IOObjectRelease(exact) }
        }
        if candidate == 0 {
            DisplaySymbols.serviceForDisplay?(display.number, &candidate)
            guard candidate != 0, IOObjectRetain(candidate) == KERN_SUCCESS else { return nil }
        }
        var count: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(candidate, &count) == KERN_SUCCESS, count > 0 else {
            IOObjectRelease(candidate); return nil
        }
        framebuffer = candidate; busCount = count
    }

    deinit { IOObjectRelease(framebuffer) }

    func transfer(_ frame: [UInt8], replyLength: Int, wait: UInt32) -> [UInt8]? {
        if replyLength == 0 && workingBus == nil { return nil }
        let buses = workingBus.map { [$0] } ?? Array(0..<busCount)
        for bus in buses {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else { continue }
            defer { IOObjectRelease(interface) }
            var connection: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, 0, &connection) == KERN_SUCCESS else { continue }
            defer { IOI2CInterfaceClose(connection, 0) }
            let types = IORegistryEntryCreateCFProperty(interface, kIOI2CTransactionTypesKey as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            var request = IOI2CRequest()
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBytes = UInt32(frame.count)
            request.replyBytes = UInt32(replyLength)
            if replyLength > 0 {
                request.minReplyDelay = UInt64(wait) * 1_000
                request.replyAddress = 0x6F
                request.replySubAddress = 0x51
                let supportsDDCReply = ((types?.uint64Value ?? 0) & (1 << kIOI2CDDCciReplyTransactionType)) != 0
                request.replyTransactionType = IOOptionBits(supportsDDCReply ? kIOI2CDDCciReplyTransactionType : kIOI2CSimpleTransactionType)
            } else {
                request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            }
            var response = [UInt8](repeating: 0, count: replyLength)
            let status = frame.withUnsafeBytes { send in
                response.withUnsafeMutableBytes { receive in
                    request.sendBuffer = vm_address_t(bitPattern: send.baseAddress)
                    request.replyBuffer = vm_address_t(bitPattern: receive.baseAddress)
                    return IOI2CSendRequest(connection, 0, &request)
                }
            }
            guard status == KERN_SUCCESS, request.result == KERN_SUCCESS else { continue }
            if replyLength > 0, DDCWire.payload(response) == nil { continue }
            workingBus = bus
            usleep(30_000)
            return response
        }
        return nil
    }
}
#endif

enum DisplayHardware {
    static let queue = DispatchQueue(label: "local.vic.windowmemory.display-hardware", qos: .userInitiated)

    static func ddc(_ display: ConnectedDisplay) -> DDCMonitor? {
        guard !display.builtIn, display.isStillConnected() else { return nil }
        #if arch(arm64)
        return AVDisplayBus(display).map { DDCMonitor(bus: $0) }
        #elseif arch(x86_64)
        return IntelDisplayBus(display).map { DDCMonitor(bus: $0) }
        #else
        return nil
        #endif
    }

    static func nativeBrightness(_ display: ConnectedDisplay) -> UInt16? {
        guard display.isStillConnected(), let get = DisplaySymbols.getBrightness, DisplaySymbols.setBrightness != nil else { return nil }
        var value: Float = 0
        guard get(display.number, &value) == 0, value.isFinite, (0...1).contains(value) else { return nil }
        return UInt16((value * 100).rounded())
    }

    static func setNativeBrightness(_ value: UInt16, for display: ConnectedDisplay) -> UInt16? {
        guard value <= 100, display.isStillConnected(),
              DisplaySymbols.setBrightness?(display.number, Float(value) / 100) == 0 else { return nil }
        return nativeBrightness(display)
    }
}
