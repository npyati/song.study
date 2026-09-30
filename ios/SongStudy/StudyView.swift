import SwiftUI

struct StudyView: View {
    @StateObject private var m: StudyModel
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var typing: Bool
    @State private var draft = ""
    @State private var editing: Note?
    @State private var renaming = false
    @State private var newTitle = ""

    init(song: Song) { _m = StateObject(wrappedValue: StudyModel(song: song)) }

    var body: some View {
        VStack(spacing: 0) {
            switch m.phase {
            case .ready: studio
            case .opening: waiting("opening…")
            case .downloading: waiting("downloading from iCloud…")
            case .failed(let why): waiting(why)
            }
        }
        .background(T.ground.ignoresSafeArea())
        .toolbar(.visible, for: .navigationBar)
        .navigationTitle(m.study.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { menu } }
        .task { await m.open() }
        .onDisappear { m.player.pause(); Task { await m.flush() } }
        .onChange(of: scenePhase) { _, p in
            if p == .background { Task { await m.flush() } }
            if p == .active { Task { await m.reloadIfChanged() } }
        }
        .sheet(item: $editing) { n in NoteEditor(note: n, m: m).presentationDetents([.medium, .large]) }
        .alert("rename study", isPresented: $renaming) {
            TextField("title", text: $newTitle)
            Button("save") { m.rename(newTitle) }
            Button("cancel", role: .cancel) {}
        }
    }

    private func waiting(_ s: String) -> some View {
        VStack { Spacer(); Text(s).font(T.mono(12)).foregroundStyle(T.ink2).multilineTextAlignment(.center).padding(30); Spacer() }
            .frame(maxWidth: .infinity)
    }

    private var studio: some View {
        VStack(spacing: 0) {
            Readouts(player: m.player, m: m)
            WaveformView(player: m.player, m: m)
                .frame(height: typing ? 96 : 138)
                .padding(.horizontal, 16)
                .animation(.easeOut(duration: 0.15), value: typing)
            Transport(player: m.player, m: m).padding(.horizontal, 16).padding(.top, 10)
            Rectangle().fill(T.line2).frame(height: 1).padding(.top, 12)
            capture.padding(.horizontal, 16).padding(.top, 12)
            Ledger(m: m, editing: $editing).padding(.top, 10)
        }
    }

    // MARK: capture

    private var capture: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(m.study.done ? "\u{2713}" : String(format: "%02d", m.study.pass))
                    .font(T.mono(11, .semibold)).foregroundStyle(T.accent)
                TextField(m.study.done ? "done — write the thesis" : "what is this pass for?",
                          text: Binding(get: { m.study.prompt(for: m.study.pass) }, set: { m.setPrompt($0) }))
                    .font(T.mono(13)).foregroundStyle(T.ink)
                    .submitLabel(.done)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(T.surface2)
            .overlay(alignment: .leading) { Rectangle().fill(T.accent).frame(width: 2) }

            HStack(alignment: .center, spacing: 8) {
                // The stamp is taken on the first keystroke. Return logs the note.
                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...4)
                    .focused($typing)
                    .submitLabel(.send)
                    .onChange(of: draft) { old, new in
                        if new.contains("\n") {
                            let text = new.replacingOccurrences(of: "\n", with: "")
                            draft = ""
                            m.commit(text)
                            return
                        }
                        if old.isEmpty && !new.isEmpty { m.arm() }
                        if new.isEmpty { m.disarm() }
                    }
                if let p = m.pending {
                    Text(fmt(p, true)).font(T.mono(11, .semibold)).foregroundStyle(T.accent)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .overlay(Rectangle().stroke(T.accent, lineWidth: 1))
                }
            }
            .padding(10)
            .background(T.surface)
            .overlay(Rectangle().stroke(typing ? T.accent : T.line2, lineWidth: 1))

            HStack {
                Text(m.hint ?? m.status)
                    .font(T.mono(10)).foregroundStyle(m.hint == nil ? T.ink3 : T.accent)
                    .lineLimit(2)
                Spacer()
                if typing {
                    Button("done") { typing = false }.buttonStyle(Key())
                }
            }
        }
    }

    private var placeholder: String {
        m.study.done ? "thesis" : "note"
    }

    // MARK: menu

    private var menu: some View {
        Menu {
            Section("lag \(String(format: "%.2f", m.study.lag))s — your reaction delay") {
                Button("lag +0.25s") { m.adjustLag(0.25) }
                Button("lag −0.25s") { m.adjustLag(-0.25) }
            }
            Section("\(m.study.targetPasses) passes") {
                Button("one more pass") { m.adjustTarget(1) }
                Button("one fewer pass") { m.adjustTarget(-1) }
            }
            Button("rename study") { newTitle = m.study.title; renaming = true }
        } label: {
            Image(systemName: "ellipsis").foregroundStyle(T.ink2)
        }
    }
}

// MARK: - readouts

struct Readouts: View {
    @ObservedObject var player: Player
    @ObservedObject var m: StudyModel

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            cell(label: sectionLabel, value: fmt(player.time, true), color: T.accent, big: true)
            Spacer(minLength: 8)
            cell(label: "remain", value: "-" + fmt(max(0, player.duration - player.time)), color: T.ink)
            Spacer(minLength: 8)
            cell(label: "pass", value: m.study.done ? "done" : "\(m.study.pass)/\(m.study.targetPasses)", color: T.ink)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var sectionLabel: String {
        let s = m.currentSection(player.time)
        return s.isEmpty ? "position" : "position · \(s)"
    }

    private func cell(label: String, value: String, color: Color, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Lbl(label)
            Text(value).font(T.mono(big ? 28 : 20)).foregroundStyle(color).monospacedDigit()
        }
    }
}

// MARK: - transport

struct Transport: View {
    @ObservedObject var player: Player
    @ObservedObject var m: StudyModel

    var body: some View {
        HStack(spacing: 8) {
            Button { player.seek(0) } label: { Image(systemName: "backward.end") }
                .buttonStyle(Key(square: 40))
            Button { player.seek(player.time - 5) } label: { Image(systemName: "gobackward.5") }
                .buttonStyle(Key(square: 40))
            Button { player.toggle() } label: {
                Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 16))
            }
            .buttonStyle(Key(on: player.playing, fill: T.accent, square: 52))
            Button { player.seek(player.time + 5) } label: { Image(systemName: "goforward.5") }
                .buttonStyle(Key(square: 40))
            Spacer()
            Button(String(format: "%.2f×", player.rate)) { m.cycleRate() }
                .buttonStyle(Key(on: player.rate != 1, fill: T.accent))
            Button("repeat") { m.repeatOn.toggle() }
                .buttonStyle(Key(on: m.repeatOn))
        }
    }
}

// MARK: - waveform

struct WaveformView: View {
    @ObservedObject var player: Player
    @ObservedObject var m: StudyModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(ctx, size) }
                .background(T.surface)
                .overlay(Rectangle().stroke(T.line, lineWidth: 1))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let d = duration
                    guard d > 0, geo.size.width > 0 else { return }
                    player.seek(max(0, min(1, v.location.x / geo.size.width)) * d)
                })
        }
    }

    private var duration: Double { max(player.duration, m.study.duration) }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let W = size.width, dur = duration
        guard dur > 0 else { return }
        let pinH: CGFloat = min(34, size.height * 0.26), heatH: CGFloat = 7
        let top = pinH, waveH = size.height - pinH - heatH - 2, mid = top + waveH / 2
        let X = { (t: Double) in CGFloat(t / dur) * W }

        ctx.fill(Path(CGRect(x: 0, y: top, width: W, height: 1)), with: .color(T.line))

        // grid
        let step: Double = dur > 420 ? 60 : 30
        var t = step
        while t < dur {
            ctx.fill(Path(CGRect(x: X(t), y: top, width: 1, height: waveH)), with: .color(T.line))
            ctx.draw(Text(fmt(t)).font(T.mono(7.5)).foregroundColor(T.ink3), at: CGPoint(x: X(t) + 3, y: top + 3), anchor: .topLeading)
            t += step
        }

        // waveform
        if !m.peaks.isEmpty {
            let n = m.peaks.count
            var path = Path()
            for (i, p) in m.peaks.enumerated() {
                let x = CGFloat(i) / CGFloat(n) * W
                let y0 = mid - CGFloat(p.y) * waveH * 0.47, y1 = mid - CGFloat(p.x) * waveH * 0.47
                path.addRect(CGRect(x: x, y: y0, width: max(0.5, W / CGFloat(n) - 0.3), height: max(1, y1 - y0)))
            }
            ctx.fill(path, with: .color(T.ink2.opacity(0.5)))
        } else {
            ctx.fill(Path(CGRect(x: 0, y: mid, width: W, height: 1)), with: .color(T.ink3.opacity(0.5)))
        }

        // sections
        for s in m.study.sections {
            let x = X(s.t)
            ctx.fill(Path(CGRect(x: x, y: top, width: 1, height: waveH)), with: .color(T.ink2.opacity(0.6)))
            ctx.draw(Text(s.sectionName).font(T.mono(8.5, .semibold)).foregroundColor(T.ink), at: CGPoint(x: x + 3, y: top + waveH - 2), anchor: .bottomLeading)
        }

        // time spent
        let hy = size.height - heatH
        let hmax = max(1, m.heat.max() ?? 1)
        for (s, v) in m.heat.enumerated() where v > 0 && Double(s) < dur {
            ctx.fill(Path(CGRect(x: X(Double(s)), y: hy, width: max(1, W / CGFloat(dur)), height: heatH)),
                     with: .color(T.accent.opacity(0.1 + v / hmax * 0.72)))
        }

        // pins, stacked by pass
        let span = CGFloat(max(1, m.study.targetPasses - 1))
        for n in m.study.notes where !n.isSection {
            let row = CGFloat(min(max(n.pass - 1, 0), m.study.targetPasses - 1)) / span
            let r = CGRect(x: X(n.t) - 3, y: 3 + row * (pinH - 14), width: 6, height: n.star ? 10 : 6)
            ctx.fill(Path(r), with: .color(T.pass(n.pass)))
            if n.id == m.selected { ctx.stroke(Path(r.insetBy(dx: -2, dy: -2)), with: .color(T.ink), lineWidth: 1) }
        }

        // playhead
        let px = X(player.time)
        ctx.fill(Path(CGRect(x: px - 1, y: top, width: 2, height: waveH)), with: .color(T.accent))
    }
}

// MARK: - ledger

struct Ledger: View {
    @ObservedObject var m: StudyModel
    @Binding var editing: Note?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Lbl("ledger")
                Lbl("\(m.study.notes.count) note\(m.study.notes.count == 1 ? "" : "s")", color: T.ink2)
                Spacer()
                if m.lastDeleted != nil {
                    Button("undo delete") { m.undoDelete() }.buttonStyle(Key())
                }
                HStack(spacing: 0) {
                    Button("pass") { m.byTime = false }.buttonStyle(Key(on: !m.byTime))
                    Button("time") { m.byTime = true }.buttonStyle(Key(on: m.byTime))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 6)

            if m.study.notes.isEmpty {
                Text("nothing logged yet").font(T.mono(11)).foregroundStyle(T.ink3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            } else {
                list
            }
        }
        .frame(maxHeight: .infinity)
        .background(T.surface2)
    }

    private var list: some View {
        List {
            if m.byTime {
                ForEach(m.study.notes.sorted { $0.t < $1.t }) { n in row(n, showPass: true) }
            } else {
                ForEach(Set(m.study.notes.map(\.pass)).sorted(), id: \.self) { p in
                    Section {
                        ForEach(m.study.notes.filter { $0.pass == p }.sorted { $0.t < $1.t }) { n in row(n, showPass: false) }
                    } header: {
                        Lbl(p > m.study.targetPasses ? "after the study" : String(format: "pass %02d", p), color: T.pass(p))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ n: Note, showPass: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Button { m.toggleStar(n) } label: {
                Text(n.star ? "\u{2605}" : "\u{2606}").font(T.mono(13)).foregroundStyle(n.star ? T.accent : T.ink3)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            Text(fmt(n.t, true)).font(T.mono(11)).foregroundStyle(n.id == m.selected ? T.accent : T.ink2)
            if showPass { Text("p\(n.pass)").font(T.mono(10)).foregroundStyle(T.pass(n.pass)) }
            if n.isSection {
                Text("= " + n.sectionName).font(T.mono(12.5, .semibold)).foregroundStyle(T.ink)
            } else {
                noteText(n.text).font(.system(size: 14.5)).foregroundStyle(T.ink)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { m.go(to: n) }
        .listRowBackground(n.id == m.selected ? T.surface : T.surface2)
        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 16))
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { m.delete(n) } label: { Label("delete", systemImage: "trash") }
            Button { editing = n } label: { Label("edit", systemImage: "pencil") }.tint(T.ink2)
        }
        .swipeActions(edge: .leading) {
            Button { m.toggleStar(n) } label: { Label(n.star ? "unflag" : "flag", systemImage: "star") }.tint(T.accent)
        }
        .contextMenu {
            Button("edit") { editing = n }
            Button(n.star ? "unflag" : "flag") { m.toggleStar(n) }
            Button("delete", role: .destructive) { m.delete(n) }
        }
    }

    /// #tags in blue.
    private func noteText(_ s: String) -> Text {
        var out = Text("")
        let words = s.components(separatedBy: " ")
        for (i, w) in words.enumerated() {
            let piece = Text(w + (i < words.count - 1 ? " " : ""))
            out = out + (w.hasPrefix("#") && w.count > 1 ? piece.foregroundColor(T.blue) : piece)
        }
        return out
    }
}

// MARK: - edit a note

struct NoteEditor: View {
    let note: Note
    @ObservedObject var m: StudyModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var t: Double

    init(note: Note, m: StudyModel) {
        self.note = note; self.m = m
        _text = State(initialValue: note.text)
        _t = State(initialValue: note.t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Lbl(String(format: "pass %02d", note.pass), color: T.pass(note.pass))
                Spacer()
                Button("cancel") { dismiss() }.buttonStyle(Key())
                Button("save") { m.update(note, text: text, t: t); dismiss() }.buttonStyle(Key(on: true, fill: T.accent))
            }
            TextEditor(text: $text)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(T.surface)
                .overlay(Rectangle().stroke(T.line2, lineWidth: 1))
                .frame(minHeight: 110)
            Lbl("move the stamp — each nudge plays a breath from the new spot")
            HStack(spacing: 8) {
                nudge("−1s", -1); nudge("−¼", -0.25)
                Text(fmt(t, true)).font(T.mono(18)).foregroundStyle(T.accent).frame(minWidth: 84)
                nudge("+¼", 0.25); nudge("+1s", 1)
            }
            Spacer()
        }
        .padding(18)
        .background(T.ground.ignoresSafeArea())
    }

    private func nudge(_ label: String, _ d: Double) -> some View {
        Button(label) {
            t = max(0, min(t + d, max(m.player.duration, m.study.duration)))
            m.audition(t)
        }
        .buttonStyle(Key())
    }
}
