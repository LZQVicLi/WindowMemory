import Foundation

struct LANMonitorAddress: Equatable {
    let host: String

    init?(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let bytes = parts.compactMap { part -> UInt8? in
            guard (1...3).contains(part.count), part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0" else { return nil }
            return UInt8(part)
        }
        guard bytes.count == 4, bytes[0] == 10 || (bytes[0] == 192 && bytes[1] == 168) ||
                (bytes[0] == 172 && (16...31).contains(bytes[1])) else { return nil }
        host = trimmed
    }

    func url(path: String, action: String, arguments: [URLQueryItem] = []) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = 6095
        components.path = "/" + path
        components.queryItems = [URLQueryItem(name: "action", value: action)] + arguments
        return components.url!
    }
}

struct LANInput: Decodable, Equatable, Identifiable {
    let sourceId: Int
    let sourceName: String
    var id: Int { sourceId }
}

struct LANMonitorSnapshot: Equatable {
    let name: String
    let inputs: [LANInput]
    let volume: Int?
}

/// HyperOS remote protocol, adapted from MonitorBar's mitv implementation.
/// See Resources/ThirdParty/MonitorBar-LICENSE.txt.
struct LANMonitor {
    let address: LANMonitorAddress
    private let request: (URL) async throws -> Data
    enum Failure: Error { case noResponse, unsupported, identityChanged }
    enum VolumeKey: String { case up = "volumeup", down = "volumedown" }
    struct Envelope<T: Decodable>: Decodable { let msg: String; let data: T? }
    private struct Device: Decodable { let devicename: String }
    private struct Sources: Decodable { let sourceList: [LANInput] }
    private struct Volume: Decodable { let volume: Int; let maxVolume: Int }
    init(address: LANMonitorAddress) {
        self.address = address
        request = Self.networkRequest
    }

    init(address: LANMonitorAddress, request: @escaping (URL) async throws -> Data) {
        self.address = address; self.request = request
    }

    func snapshot() async throws -> LANMonitorSnapshot {
        let name = try await deviceName()
        async let sources = try? inputs()
        async let audio = try? volume()
        let (choices, level) = await (sources ?? [], audio)
        guard !choices.isEmpty || level != nil else { throw Failure.unsupported }
        return LANMonitorSnapshot(name: name, inputs: choices, volume: level)
    }

    func select(_ source: LANInput, pairedName: String) async throws {
        guard try await deviceName() == pairedName else { throw Failure.identityChanged }
        guard try await inputs().contains(source) else { throw Failure.unsupported }
        try Task.checkCancellation()
        try await send("changesource2", key: "sourceid", value: String(source.id))
    }

    func changeVolume(_ key: VolumeKey, pairedName: String) async throws -> Int? {
        guard try await deviceName() == pairedName else { throw Failure.identityChanged }
        try Task.checkCancellation()
        try await send("keyevent", key: "keycode", value: key.rawValue)
        try await Task.sleep(for: .milliseconds(150))
        return try? await volume()
    }

    private func deviceName() async throws -> String {
        let value: Device = try await read("request", "isalive")
        let name = String(value.devicename.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !name.isEmpty else { throw Failure.unsupported }
        return name
    }

    private func inputs() async throws -> [LANInput] {
        let result: Sources = try await read("controller", "getsources")
        var seen = Set<Int>()
        return result.sourceList.prefix(64).compactMap {
            guard (0...65535).contains($0.id), seen.insert($0.id).inserted else { return nil }
            let name = $0.id == 29 ? "DP" : ($0.id == 30 ? "USB-C" : String($0.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)))
            return name.isEmpty ? nil : LANInput(sourceId: $0.id, sourceName: name)
        }
    }

    private func volume() async throws -> Int {
        let v: Volume = try await read("controller", "getvolume")
        guard (1...10_000).contains(v.maxVolume), (0...v.maxVolume).contains(v.volume) else { throw Failure.unsupported }
        return v.volume * 100 / v.maxVolume
    }

    private func read<T: Decodable>(_ path: String, _ action: String) async throws -> T {
        let body = try await request(address.url(path: path, action: action))
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: body)
        guard envelope.msg == "success", let value = envelope.data else { throw Failure.unsupported }
        return value
    }

    private func send(_ action: String, key: String, value: String) async throws {
        struct Acknowledgement: Decodable { let msg: String }
        let body = try await request(address.url(path: "controller", action: action,
                                                 arguments: [URLQueryItem(name: key, value: value)]))
        guard try JSONDecoder().decode(Acknowledgement.self, from: body).msg == "success" else { throw Failure.unsupported }
    }

    private static func networkRequest(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.connectionProxyDictionary = ["HTTPEnable": 0, "HTTPSEnable": 0, "SOCKSEnable": 0, "ProxyAutoConfigEnable": 0]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url), delegate: RejectRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url == url else { throw Failure.noResponse }
        var result = Data()
        for try await byte in bytes {
            guard result.count < 64 * 1024 else { throw Failure.noResponse }
            result.append(byte)
        }
        return result
    }

    private final class RejectRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
