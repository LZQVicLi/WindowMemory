import Foundation

func runUpdateTests() -> Int {
    var count = 0
    func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        count += 1
        print("PASS: \(name)")
    }
    let installed = ReleaseVersion("1.4.0")!
    let name = "WindowMemory-v1.10.0-universal.zip"
    let url = "https://github.com/LZQVicLi/WindowMemory/releases/download/v1.10.0/\(name)"
    let sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    func feed(tag: String = "v1.10.0", prerelease: Bool = false, draft: Bool = false,
              path: String? = nil, digest: String? = nil, size: Int = 3) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": tag, "draft": draft, "prerelease": prerelease,
            "assets": [["name": name, "state": "uploaded", "size": size,
                        "digest": digest ?? ("sha256:" + sha256), "browser_download_url": path ?? url]]
        ])
    }

    let release = try! ProjectRelease.resolve(feed(), installed: installed)
    check(release?.version.description == "1.10.0", "updates compare numeric version components")
    check(ReleaseVersion("1.4.0-rc1") == nil && ReleaseVersion("01.4.0") == nil,
          "only canonical stable version numbers are accepted")
    check(try! ProjectRelease.resolve(feed(tag: "v1.4.0"), installed: installed) == nil &&
          ProjectRelease.resolve(feed(tag: "v1.3.1"), installed: installed) == nil,
          "current and older versions are never installed")
    check(try! ProjectRelease.resolve(feed(prerelease: true), installed: installed) == nil &&
          ProjectRelease.resolve(feed(draft: true), installed: installed) == nil, "drafts and prereleases are ignored")
    check(try! ProjectRelease.resolve(feed(path: "https://example.com/" + name), installed: installed)?.package == nil &&
          ProjectRelease.resolve(feed(digest: "sha256:0000"), installed: installed)?.package == nil &&
          ProjectRelease.resolve(feed(size: Int.max), installed: installed)?.package == nil,
          "untrusted URLs, missing digest data and oversized assets fall back to manual download")
    check(release?.package?.matches(Data("abc".utf8)) == true &&
          release?.package?.matches(Data("abd".utf8)) == false &&
          release?.package?.matches(Data("abc!".utf8)) == false, "update verification rejects tampered data and wrong sizes")
    check(AppUpdateInstaller.safeArchiveEntry("窗口记忆.app/Contents/Info.plist") &&
          !AppUpdateInstaller.safeArchiveEntry("窗口记忆.app/../other") &&
          !AppUpdateInstaller.safeArchiveEntry("/窗口记忆.app/Contents") &&
          !AppUpdateInstaller.safeArchiveEntry("Other.app/Contents"), "update archives cannot escape the expected bundle")
    check(!UpdateArchive.validate(Data([0x50, 0x4B, 0x05, 0x06])) &&
          !UpdateArchive.validate(Data(repeating: 0xFF, count: 512)), "invalid ZIP indexes are rejected without extraction")

    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("wm-update-test-" + UUID().uuidString, isDirectory: true)
    try! fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
    try! Data("previous".utf8).write(to: old)
    try! Data("replacement".utf8).write(to: new)
    check(AppUpdateInstaller.swap(old, new) && (try? String(contentsOf: old, encoding: .utf8)) == "replacement" &&
          (try? String(contentsOf: new, encoding: .utf8)) == "previous", "atomic swap preserves the previous bundle")
    check(AppUpdateInstaller.swap(old, new) && (try? String(contentsOf: old, encoding: .utf8)) == "previous",
          "atomic rollback restores the previous contents")
    return count
}

/// Checks staging and signatures without replacing or launching any bundle.
func verifyUpdateArchive(_ zip: URL, version: ReleaseVersion) throws {
    let fm = FileManager.default
    let directory = fm.temporaryDirectory.appendingPathComponent("wm-archive-test-" + UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? fm.removeItem(at: directory) }
    _ = try AppUpdateInstaller.stage(zip, in: directory, for: version, installedAt: Bundle.main.bundleURL)
}

/// Validates an actual public Release end to end without replacing or launching it.
func runUpdateDiagnostics() -> Never {
    Task.detached {
        do {
            guard let release = try await UpdateNetwork.latest(installed: ReleaseVersion("0.0.0")!),
                  let package = release.package else { throw UpdateIssue.feed }
            let fm = FileManager.default
            let directory = fm.temporaryDirectory.appendingPathComponent("wm-update-probe-" + UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                let zip = directory.appendingPathComponent("update.zip")
                try await UpdateNetwork.download(package, to: zip)
                try verifyUpdateArchive(zip, version: release.version)
                print("Verified public release v\(release.version): HTTPS, SHA-256, safe ZIP, bundle metadata, and signature.")
                try fm.removeItem(at: directory)
            } catch {
                try? fm.removeItem(at: directory)
                throw error
            }
            exit(EXIT_SUCCESS)
        } catch {
            print("Update diagnostics failed: \(error)")
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}
