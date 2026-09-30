import Foundation

/// Everything that touches iCloud goes through NSFileCoordinator: a coordinated
/// read of a file that hasn't downloaded yet waits for it, and a coordinated
/// write can't collide with iCloud syncing the same file.
enum Files {
    static let fm = FileManager.default

    static func read(_ url: URL) throws -> Data {
        try? fm.startDownloadingUbiquitousItem(at: url)
        var coordErr: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordErr) { u in
            result = Result { try Data(contentsOf: u) }
        }
        if let coordErr { throw coordErr }
        return try result.get()
    }

    static func write(_ data: Data, to url: URL) throws {
        var coordErr: NSError?
        var writeErr: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordErr) { u in
            do { try data.write(to: u, options: .atomic) } catch { writeErr = error }
        }
        if let e = coordErr ?? (writeErr as NSError?) { throw e }
    }

    /// The file itself, or iCloud's placeholder for it (".Name.ext.icloud").
    static func exists(_ url: URL) -> Bool {
        if fm.fileExists(atPath: url.path) { return true }
        let ph = url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
        return fm.fileExists(atPath: ph.path)
    }

    static func modDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func isDownloaded(_ url: URL) -> Bool {
        guard fm.fileExists(atPath: url.path) else { return false }
        let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = v?.ubiquitousItemDownloadingStatus else { return true }   // not an iCloud item
        return status == .current
    }

    /// A local copy for playback. Downloads from iCloud if needed; reuses the
    /// cached copy when the size matches.
    static func localAudio(for url: URL) throws -> URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("audio", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(url.lastPathComponent)
        try? fm.startDownloadingUbiquitousItem(at: url)
        var coordErr: NSError?
        var copyErr: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordErr) { u in
            do {
                let src = try fm.attributesOfItem(atPath: u.path)[.size] as? NSNumber
                if let have = try? fm.attributesOfItem(atPath: dest.path)[.size] as? NSNumber, have == src { return }
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: u, to: dest)
            } catch { copyErr = error }
        }
        if let e = coordErr ?? (copyErr as NSError?) { throw e }
        return dest
    }
}

/// The heat band (seconds actually listened to) is playback telemetry. Like the
/// web app, it stays on the device so the notes file stays readable.
enum HeatStore {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("heat", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func url(_ key: String) -> URL { dir.appendingPathComponent(key.replacingOccurrences(of: "/", with: "_") + ".json") }
    static func load(_ key: String) -> [Double] {
        guard let d = try? Data(contentsOf: url(key)) else { return [] }
        return (try? JSONDecoder().decode([Double].self, from: d)) ?? []
    }
    static func save(_ key: String, _ heat: [Double]) {
        if let d = try? JSONEncoder().encode(heat.map { ($0 * 100).rounded() / 100 }) { try? d.write(to: url(key), options: .atomic) }
    }
}

/// A local copy of every notes file written — insurance if folder access is ever lost.
enum Backup {
    static func write(_ text: String, name: String) {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("backup", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try? text.write(to: d.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}
