import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if library.folder == nil { welcome } else { list }
            }
            .background(T.ground.ignoresSafeArea())
            // our own flat header — the system bar wraps items in glass bubbles
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Song.self) { song in StudyView(song: song) }
            .sheet(isPresented: $picking) {
                FolderPicker { library.choose($0) }.ignoresSafeArea()
            }
            .onChange(of: scenePhase) { _, p in if p == .active { library.refresh() } }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Rectangle().fill(T.accent).frame(width: 7, height: 7)
                Text("song.study").font(T.mono(14, .semibold)).foregroundStyle(T.ink)
                Spacer()
                if library.folder != nil {
                    Text(library.folder?.lastPathComponent ?? "").font(T.mono(11)).foregroundStyle(T.ink3).lineLimit(1)
                    Button("folder") { picking = true }.buttonStyle(Key())
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            Rectangle().fill(T.line2).frame(height: 1)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = library.problem { Text(p).font(T.mono(11)).foregroundStyle(T.accent) }
            Button("choose a folder") { picking = true }
                .buttonStyle(Key(on: true, fill: T.accent))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var list: some View {
        List {
            Section {
                if library.songs.isEmpty {
                    Text("no audio in this folder").font(T.mono(11)).foregroundStyle(T.ink3)
                        .listRowBackground(T.surface)
                }
                ForEach(library.songs) { song in
                    NavigationLink(value: song) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.system(size: 15)).foregroundStyle(T.ink)
                            HStack(spacing: 10) {
                                if song.hasNotes { Lbl("notes", color: T.accent) }
                                if !song.downloaded { Lbl("icloud") }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .listRowBackground(T.surface)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { library.refresh() }
    }
}
