import AppKit
import CryptoKit
import Security
import SwiftUI

struct ReleaseVersion: Comparable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 9, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  part.count == 1 || part.first != "0" else { return nil }
            return Int(part)
        }
        guard values.count == 3 else { return nil }
        (major, minor, patch) = (values[0], values[1], values[2])
    }

    var description: String { "\(major).\(minor).\(patch)" }
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct UpdatePackage: Equatable {
    let url: URL
    let size: Int
    let sha256: String

    func matches(_ data: Data) -> Bool {
        data.count == size && SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256
    }
}

struct ProjectRelease: Equatable {
    static let repo = "LZQVicLi/WindowMemory"
    static let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    static let releases = URL(string: "https://github.com/\(repo)/releases/latest")!
    static let maximumArchiveSize = 64 * 1024 * 1024

    let version: ReleaseVersion
    let package: UpdatePackage?
    var page: URL { URL(string: "https://github.com/\(Self.repo)/releases/tag/v\(version)")! }

    private struct Feed: Decodable {
        struct Asset: Decodable {
            let name: String
            let state: String
            let size: Int
            let digest: String?
            let browser_download_url: String
        }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    static func resolve(_ data: Data, installed: ReleaseVersion) throws -> ProjectRelease? {
        let feed = try JSONDecoder().decode(Feed.self, from: data)
        guard !feed.draft, !feed.prerelease else { return nil }
        guard feed.tag_name.first == "v", let version = ReleaseVersion(String(feed.tag_name.dropFirst())) else { throw UpdateIssue.feed }
        guard version > installed else { return nil }
        let name = "WindowMemory-v\(version)-universal.zip"
        let expected = "https://github.com/\(repo)/releases/download/v\(version)/\(name)"
        let assets = feed.assets.filter { $0.name == name }
        var package: UpdatePackage?
        if assets.count == 1, let asset = assets.first,
           asset.state == "uploaded", asset.browser_download_url == expected,
           (1...maximumArchiveSize).contains(asset.size),
           let digest = asset.digest, digest.hasPrefix("sha256:") {
            let hex = String(digest.dropFirst(7)).lowercased()
            if hex.utf8.count == 64, hex.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) {
                package = UpdatePackage(url: URL(string: expected)!, size: asset.size, sha256: hex)
            }
        }
        return ProjectRelease(version: version, package: package)
    }
}

enum UpdateIssue: Error {
    case feed, download, integrity, archive, app, destination, install, launch, rollback(String)
}

/// Cookies, credentials and user data are not needed for the public release API.
private final class UpdateRedirects: NSObject, URLSessionTaskDelegate {
    let allowed: Set<String>
    init(_ allowed: Set<String>) { self.allowed = allowed }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(permits(request.url) ? request : nil)
    }
    func permits(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.port == nil, url.user == nil, url.password == nil,
              let host = url.host else { return false }
        return allowed.contains(host)
    }
}

enum UpdateNetwork {
    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": "WindowMemory/\(appVersion)"]
        return URLSession(configuration: configuration)
    }

    static func latest(installed: ReleaseVersion) async throws -> ProjectRelease? {
        let session = session()
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: ProjectRelease.api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let redirects = UpdateRedirects(["api.github.com"])
        let (data, response) = try await session.data(for: request, delegate: redirects)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              redirects.permits(http.url), data.count <= 2 * 1024 * 1024 else { throw UpdateIssue.feed }
        return try ProjectRelease.resolve(data, installed: installed)
    }

    static func download(_ package: UpdatePackage, to destination: URL) async throws {
        let session = session()
        defer { session.finishTasksAndInvalidate() }
        let redirects = UpdateRedirects(["github.com", "release-assets.githubusercontent.com",
                                         "objects.githubusercontent.com", "github-releases.githubusercontent.com"])
        let (file, response) = try await session.download(for: URLRequest(url: package.url), delegate: redirects)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, redirects.permits(http.url),
              try file.resourceValues(forKeys: [.fileSizeKey]).fileSize == package.size else { throw UpdateIssue.download }
        guard package.matches(try Data(contentsOf: file, options: .mappedIfSafe)) else { throw UpdateIssue.integrity }
        try FileManager.default.moveItem(at: file, to: destination)
    }
}

struct StagedAppUpdate {
    let directory: URL
    let replacement: URL
}

enum AppUpdateInstaller {
    static let identifier = "local.vic.windowmemory"
    static let appName = "窗口记忆.app"

    static func canInstall(at destination: URL) -> Bool {
        let fm = FileManager.default
        let root = destination.deletingLastPathComponent().resolvingSymlinksInPath().path
        let homes = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").resolvingSymlinksInPath().path]
        let symlink = (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? true
        return destination.pathExtension == "app" && !symlink && homes.contains(root) &&
            fm.isWritableFile(atPath: root) && Bundle(url: destination)?.bundleIdentifier == identifier
    }

    static func installedVersion(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    static func prepare(_ release: ProjectRelease, at destination: URL) async throws -> StagedAppUpdate {
        guard let package = release.package, canInstall(at: destination) else { throw UpdateIssue.destination }
        let fm = FileManager.default
        let directory = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination, create: true)
        do {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let zip = directory.appendingPathComponent("update.zip")
            try await UpdateNetwork.download(package, to: zip)
            return try stage(zip, in: directory, for: release.version, installedAt: destination)
        } catch {
            try? fm.removeItem(at: directory)
            throw error
        }
    }

    static func stage(_ zip: URL, in directory: URL, for version: ReleaseVersion, installedAt destination: URL) throws -> StagedAppUpdate {
        let fm = FileManager.default
        guard UpdateArchive.validate(try Data(contentsOf: zip, options: .mappedIfSafe)) else { throw UpdateIssue.archive }
        let extracted = directory.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        let app = extracted.appendingPathComponent(appName, isDirectory: true)
        try verify(app, version: version, installedAt: destination)
        try preserveQuarantine(on: app, from: [zip, destination])
        return StagedAppUpdate(directory: directory, replacement: app)
    }

    static func safeArchiveEntry(_ entry: String) -> Bool {
        let parts = entry.split(separator: "/")
        guard !entry.hasPrefix("/"), !entry.contains("\\"), !entry.unicodeScalars.contains(where: { $0.value < 32 }),
              !parts.contains("."), !parts.contains(".."), let root = parts.first else { return false }
        return root == appName || root == "__MACOSX"
    }

    static func verify(_ app: URL, version: ReleaseVersion, installedAt destination: URL) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard app.resolvingSymlinksInPath().lastPathComponent == appName,
              let data = try? Data(contentsOf: plist),
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == identifier,
              info["CFBundleExecutable"] as? String == "WindowMemory",
              info["CFBundlePackageType"] as? String == "APPL",
              info["CFBundleShortVersionString"] as? String == version.description,
              info["CFBundleVersion"] as? String == version.description,
              info["WindowMemoryDemo"] as? Bool != true else { throw UpdateIssue.app }
        let flags = SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate))
        var requirement: SecRequirement?
        var rule = "identifier \"\(identifier)\""
        // A future Developer ID installation must not be downgraded to an
        // ad-hoc update or switched to another signing team.
        if let team = try signingTeam(destination) {
            guard !team.isEmpty, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { throw UpdateIssue.app }
            rule += " and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        }
        var code: SecStaticCode?
        guard SecRequirementCreateWithString(rule as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { throw UpdateIssue.app }
    }

    private static func signingTeam(_ app: URL) throws -> String? {
        var code: SecStaticCode?, info: CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess else { throw UpdateIssue.app }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Swaps complete bundles on the same filesystem. No executable is
    /// overwritten in place; the previous bundle remains available to roll back.
    static func swap(_ lhs: URL, _ rhs: URL) -> Bool {
        renameatx_np(AT_FDCWD, lhs.path, AT_FDCWD, rhs.path, UInt32(RENAME_SWAP)) == 0
    }

    static func retainPrevious(_ app: URL, version: String) throws {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WindowMemory/Update Backups", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep old bundle contents without another discoverable .app identity.
        let backup = base.appendingPathComponent("WindowMemory-v\(version)-\(UUID().uuidString).backup")
        try fm.moveItem(at: app, to: backup)
    }

    private static func run(_ executable: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateIssue.archive }
    }

    private static func preserveQuarantine(on app: URL, from sources: [URL]) throws {
        let name = "com.apple.quarantine"
        if getxattr(app.path, name, nil, 0, 0, XATTR_NOFOLLOW) > 0 { return }
        for source in sources {
            let length = getxattr(source.path, name, nil, 0, 0, XATTR_NOFOLLOW)
            if length < 0, errno != ENOATTR { throw UpdateIssue.app }
            guard length > 0 else { continue }
            guard length <= 8192 else { throw UpdateIssue.app }
            var bytes = [UInt8](repeating: 0, count: length)
            let read = bytes.withUnsafeMutableBytes { getxattr(source.path, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW) }
            guard read == length, bytes.withUnsafeBytes({
                setxattr(app.path, name, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
            }) == 0 else { throw UpdateIssue.app }
            return
        }
    }
}
