import Foundation

/// Validate the central directory before giving a known release ZIP to ditto.
enum UpdateArchive {
    static func validate(_ bytes: Data) -> Bool {
        guard bytes.startIndex == 0, bytes.count >= 22, bytes.count <= ProjectRelease.maximumArchiveSize else { return false }
        func u16(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p+1]) << 8 }
        func u32(_ p: Int) -> Int { u16(p) | u16(p+2) << 16 }
        let last = bytes.count - 22
        guard let end = stride(from: last, through: max(0, last - 65535), by: -1).first(where: {
            u32($0) == 0x06054B50 && $0 + 22 + u16($0+20) == bytes.count
        }), u16(end+4) == 0, u16(end+6) == 0 else { return false }
        let count = u16(end+10), start = u32(end+16)
        guard (1...2_000).contains(count), u16(end+8) == count, start + u32(end+12) == end else { return false }
        var p = start, total = 0, foundApp = false
        var paths = Set<String>()
        func validExtra(_ start: Int, _ end: Int) -> Bool {
            var q = start
            while q < end {
                guard q + 4 <= end else { return false }
                let type = u16(q), length = u16(q+2)
                // Disallow ZIP64 and Unicode path overrides. ditto release
                // archives carry the UTF-8 path directly, plus timestamp data.
                guard type != 0x0001, type != 0x7075, q+4+length <= end else { return false }
                q += 4+length
            }
            return true
        }
        for _ in 0..<count {
            guard p + 46 <= end, u32(p) == 0x02014B50, u16(p+8) & 1 == 0, u16(p+34) == 0 else { return false }
            let nameLength = u16(p+28), extraLength = u16(p+30)
            let nameStart = p + 46, nameEnd = nameStart + nameLength
            let next = nameEnd + extraLength + u16(p+32)
            let mode = (u32(p+38) >> 16) & 0xF000
            let compression = u16(p+10)
            guard next <= end, [0, 0x4000, 0x8000].contains(mode), [0, 8].contains(compression),
                  let name = String(data: bytes[nameStart..<nameEnd], encoding: .utf8),
                  AppUpdateInstaller.safeArchiveEntry(name),
                  paths.insert(name.split(separator: "/").joined(separator: "/").precomposedStringWithCanonicalMapping.lowercased()).inserted,
                  validExtra(nameEnd, nameEnd + extraLength) else { return false }
            let local = u32(p+42), compressed = u32(p+20)
            guard local + 30 <= start, u32(local) == 0x04034B50, u16(local+6) == u16(p+8),
                  u16(local+8) == compression, u16(local+26) == nameLength else { return false }
            let localName = local + 30, localEnd = localName + nameLength
            let payload = localEnd + u16(local+28)
            guard payload + compressed <= start, bytes[localName..<localEnd].elementsEqual(bytes[nameStart..<nameEnd]),
                  validExtra(localEnd, payload) else { return false }
            total += u32(p+24)
            guard total <= 128 * 1024 * 1024 else { return false }
            if name == AppUpdateInstaller.appName + "/" { foundApp = true }
            p = next
        }
        return foundApp && p == end
    }
}
