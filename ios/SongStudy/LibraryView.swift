import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: Library
    @Environment(\.scenePhase) private var scenePhase
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Group {
                if library.folder == nil { welcome } else { list }
            }
            .background(T.ground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 7) {
                        Rectangle().fill(T.accent).frame(width: 7, height: 7)
                        Text("song.study").font(T.mono(13, .semibold)).foregroundStyle(T.ink)
                    }
                }
                if library.folder != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("folder") { picking = true }.buttonStyle(Key())
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Song.self) { song in StudyView(song: song) }
            .sheet(isPresented: $picking) {
                FolderPicker { library.choose($0) }.ignoresSafeArea()
            }
            .onChange(of: scenePhase) { _, p in if p == .active { library.refresh() } }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("Listen to one song ten times. Write down what you hear.")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(T.ink)
            Text("Pick a folder in iCloud Drive. Put your MP3s in it from your Mac; your notes are saved beside each one as a .notes.md file — the same files the web app reads.")
                .font(.system(size: 15)).foregroundStyle(T.ink2)
            if let p = library.problem { Text(p).font(T.mono(11)).foregroundStyle(T.accent) }
            Button("choose a folder") { picking = true }
                .buttonStyle(Key(on: true, fill: T.accent))
            Spacer(); Spacer()
        }
        .padding(24)
    }

    private var list: some View {
        List {
            Section {
                if library.songs.isEmpty {
                    Text("No audio in \(library.folder?.lastPathComponent ?? "this folder") yet. Add MP3s from your Mac — iCloud Drive › \(library.folder?.lastPathComponent ?? "") — then pull to refresh.")
                        .font(.system(size: 14)).foregroundStyle(T.ink2)
                        .listRowBackground(T.surface)
                }
                ForEach(library.songs) { song in
                    NavigationLink(value: song) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title).font(.system(size: 15)).foregroundStyle(T.ink)
                            HStack(spacing: 10) {
                                if song.hasNotes { Lbl("notes", color: T.accent) }
                                if !song.downloaded { Lbl("in icloud — downloads when opened") }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .listRowBackground(T.surface)
                }
            } header: {
                Lbl(library.folder?.lastPathComponent ?? "")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { library.refresh() }
    }
}
