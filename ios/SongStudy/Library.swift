import Foundation
import SwiftUI

struct Song: Identifiable, Hashable {
    let url: URL
    let downloaded: Bool
    let hasNotes: Bool
    var id: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
    /// Same name the web app suggests, so a study made on either side is found by the other.
    var notesURL: URL { url.deletingLastPathComponent().appendingPathComponent(title + ".notes.md") }
}

@MainActor
final class Library: ObservableObject {
    @Published var folder: URL?
    @Published var songs: [Song] = []
    @Published var problem: String?

    private let key = "songstudy.folderBookmark"
    static let audioExt: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]

    init() { restore() }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            problem = "Lost access to the folder. Choose it again."
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: key) }
        folder = url
        refresh()
    }

    func choose(_ url: URL) {
        folder?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else {
            problem = "iOS didn't grant access to that folder."
            return
        }
        if let data = try? url.bookmarkData() { UserDefaults.standard.set(data, forKey: key) }
        folder = url
        problem = nil
        refresh()
    }

    func refresh() {
        guard let folder else { return }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var present = Set<String>(), cloud = Set<String>()
        for n in names {
            if n.hasPrefix("."), n.hasSuffix(".icloud") { cloud.insert(String(n.dropFirst().dropLast(7))) }
            else if !n.hasPrefix(".") { present.insert(n) }
        }
        let all = present.union(cloud)
        songs = all
            .filter { Self.audioExt.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { n in
                let url = folder.appendingPathComponent(n)
                let notes = (n as NSString).deletingPathExtension + ".notes.md"
                return Song(url: url, downloaded: present.contains(n) && Files.isDownloaded(url), hasNotes: all.contains(notes))
            }
    }
}
