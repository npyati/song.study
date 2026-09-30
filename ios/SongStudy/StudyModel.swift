import Foundation
import SwiftUI

@MainActor
final class StudyModel: ObservableObject {
    let song: Song
    let player = Player()

    @Published var study: Study
    @Published var peaks: [SIMD2<Float>] = []
    @Published var heat: [Double] = []
    @Published var phase: Phase = .opening
    @Published var pending: Double?
    @Published var selected: UUID?
    @Published var byTime = false
    @Published var repeatOn = true
    @Published var hint: String?
    @Published var status = ""
    @Published var lastDeleted: Note?

    enum Phase: Equatable { case opening, downloading, ready, failed(String) }

    static let preroll = 4.0
    private var heard = Set<Int>()
    private var counted = false
    private var auditionEnd: Double?
    private var lastSeen: Date?
    private var saveTask: Task<Void, Never>?
    private var savePending = false
    private var hintTask: Task<Void, Never>?
    private var heatDirty = false

    init(song: Song) {
        self.song = song
        self.study = Study(title: song.title, fileName: song.url.lastPathComponent)
    }

    // MARK: open

    func open() async {
        heat = HeatStore.load(song.id)
        await loadNotes()
        phase = song.downloaded ? .opening : .downloading
        let src = song.url
        do {
            let local = try await Task.detached(priority: .userInitiated) { try Files.localAudio(for: src) }.value
            player.onTick = { [weak self] t, dt, playing in self?.tick(t, dt, playing) }
            player.onEnd = { [weak self] in self?.reachedEnd() }
            player.load(local, title: study.title)
            phase = .ready
            peaks = await Task.detached(priority: .utility) { await Peaks.compute(local) }.value
        } catch {
            phase = .failed("Couldn't get \(song.url.lastPathComponent) from iCloud. Check that it has finished uploading.")
        }
    }

    private func loadNotes() async {
        let url = song.notesURL
        guard Files.exists(url) else { return }
        let fileName = song.url.lastPathComponent
        if let text = try? await Task.detached(priority: .userInitiated, operation: { try String(decoding: Files.read(url), as: UTF8.self) }).value {
            var st = MD.parse(text, fileName: url.lastPathComponent)
            st.fileName = fileName
            study = st
            lastSeen = Files.modDate(url)
        }
    }

    // MARK: the frame loop

    private func tick(_ t: Double, _ dt: Double, _ playing: Bool) {
        let dur = player.duration
        if dur > 0, study.duration != dur { study.duration = dur }
        if playing, dt > 0 {
            let s = Int(t)
            if s >= 0 {
                if heat.count <= s { heat += Array(repeating: 0, count: s - heat.count + 1) }
                heat[s] += dt                  // song-seconds, not wall clock
                heard.insert(s)
                heatDirty = true
            }
        }
        if let end = auditionEnd, t >= end { player.pause(); auditionEnd = nil }
        guard playing, dur > 0 else { return }
        if t < 1 { counted = false }
        if !counted && t >= dur - 0.35 { crossedEnd() }
    }

    private func reachedEnd() {
        if !counted { crossedEnd() }
    }

    /// A pass only counts if three quarters of the song was actually heard.
    private func crossedEnd() {
        counted = true
        let enough = heard.count >= Int(player.duration * 0.75)
        heard = []
        if enough { completePass() }
        else {
            flash("that pass didn't count — less than three quarters of the song was heard")
            if repeatOn { player.seek(0); player.play() }
        }
    }

    private func completePass() {
        guard !study.done else { return }
        study.pass += 1
        save()
        if study.done {
            player.pause(); player.seek(0)
            flash("study complete — \(study.targetPasses) passes. write the thesis.")
        } else if repeatOn {
            player.seek(0); player.play()
        } else {
            player.seek(0)
        }
    }

    // MARK: notes

    /// Reaction delay in song time: none while paused (you're placed, not late),
    /// and scaled by playback rate.
    var effLag: Double { player.playing ? study.lag * Double(player.rate) : 0 }

    func arm() {
        pending = clamp(player.time - effLag)
    }
    func disarm() { pending = nil }

    func commit(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let t = pending ?? clamp(player.time - effLag)
        study.notes.append(Note(t: t, text: text, pass: study.pass))
        study.notes.sort { $0.t < $1.t }
        pending = nil
        save()
    }

    func go(to n: Note) {
        selected = n.id
        auditionEnd = nil
        player.seek(max(0, n.t - Self.preroll))
        player.play()
    }

    func toggleStar(_ n: Note) {
        guard let i = study.notes.firstIndex(where: { $0.id == n.id }) else { return }
        study.notes[i].star.toggle()
        save()
    }

    func delete(_ n: Note) {
        study.notes.removeAll { $0.id == n.id }
        lastDeleted = n
        if selected == n.id { selected = nil }
        save()
    }

    func undoDelete() {
        guard let n = lastDeleted else { return }
        study.notes.append(n)
        study.notes.sort { $0.t < $1.t }
        lastDeleted = nil
        save()
    }

    func update(_ n: Note, text: String, t: Double) {
        guard let i = study.notes.firstIndex(where: { $0.id == n.id }) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { delete(n); return }
        study.notes[i].text = clean
        study.notes[i].t = clamp(t)
        study.notes.sort { $0.t < $1.t }
        save()
    }

    /// Play a breath from a moment, then stop.
    func audition(_ t: Double) {
        player.seek(max(0, t - 0.25))
        auditionEnd = t + 1.5
        player.play()
    }

    func currentSection(_ t: Double) -> String {
        var name = ""
        for n in study.sections { if n.t <= t + 0.05 { name = n.sectionName } else { break } }
        return name
    }

    // MARK: settings

    func setPrompt(_ s: String) { study.setPrompt(s, for: study.pass); save() }
    func adjustLag(_ d: Double) { study.lag = min(6, max(0, study.lag + d)); save() }
    func adjustTarget(_ d: Int) { study.targetPasses = min(40, max(1, study.targetPasses + d)); save() }
    func rename(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        study.title = t; player.title = t; player.publishNowPlaying(); save()
    }
    func cycleRate() {
        let next: Float = player.rate == 1 ? 0.75 : player.rate == 0.75 ? 0.5 : 1
        player.setRate(next)
    }

    // MARK: saving

    func save() {
        savePending = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.writeNow()
        }
    }

    func flush() async {
        saveTask?.cancel()
        if savePending { await writeNow() }
        if heatDirty { HeatStore.save(song.id, heat); heatDirty = false }
    }

    private func writeNow() async {
        savePending = false
        let url = song.notesURL
        // someone edited the file since we last touched it — fold that in first
        if let m = Files.modDate(url), let seen = lastSeen, m.timeIntervalSince(seen) > 0.5 {
            await mergeExternal()
        }
        let text = MD.write(study)
        let ok = await Task.detached(priority: .utility) { (try? Files.write(Data(text.utf8), to: url)) != nil }.value
        lastSeen = Files.modDate(url)
        Backup.write(text, name: url.lastPathComponent)
        status = ok ? "saved " + Date().formatted(date: .omitted, time: .shortened) : "couldn't write \(url.lastPathComponent)"
        if heatDirty { HeatStore.save(song.id, heat); heatDirty = false }
    }

    /// Take the file, then put back any local note it doesn't have. Nothing is dropped.
    private func mergeExternal() async {
        let url = song.notesURL
        guard let text = try? await Task.detached(operation: { try String(decoding: Files.read(url), as: UTF8.self) }).value else { return }
        var outside = MD.parse(text, fileName: url.lastPathComponent)
        outside.fileName = study.fileName
        let have = Set(outside.notes.map(\.key))
        for n in study.notes where !have.contains(n.key) { outside.notes.append(n) }
        outside.notes.sort { $0.t < $1.t }
        study = outside
        lastSeen = Files.modDate(url)
    }

    /// Coming back to the app: pick up edits made on the Mac meanwhile.
    func reloadIfChanged() async {
        let url = song.notesURL
        guard let m = Files.modDate(url), let seen = lastSeen, m.timeIntervalSince(seen) > 0.5 else { return }
        if savePending { await mergeExternal(); save() }
        else {
            let fileName = study.fileName
            guard let text = try? await Task.detached(operation: { try String(decoding: Files.read(url), as: UTF8.self) }).value else { return }
            var st = MD.parse(text, fileName: url.lastPathComponent)
            st.fileName = fileName
            study = st
            lastSeen = m
            status = "reloaded — the notes changed on another device"
        }
    }

    // MARK: helpers

    private func clamp(_ t: Double) -> Double { min(max(0, t), max(player.duration, study.duration)) }

    func flash(_ s: String) {
        hint = s
        hintTask?.cancel()
        hintTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled { self?.hint = nil }
        }
    }
}
