import SwiftUI
import SwiftData

enum SidebarCategory: Hashable {
    case allSongs
    case artist(String)
    case album(String)
    case genre(String)
    case playlist(PersistentIdentifier)
}

// MARK: - Focused Value for Menu Commands

private struct CreatePlaylistAction: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var createPlaylist: (() -> Void)? {
        get { self[CreatePlaylistAction.self] }
        set { self[CreatePlaylistAction.self] = newValue }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Query(sort: \Song.artist) private var songs: [Song]
    @Query(sort: \Playlist.name) private var playlists: [Playlist]
    @Binding var selection: SidebarCategory?
    @Binding var editingPlaylistID: PersistentIdentifier?
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext

    private var artists: [String] {
        Array(Set(songs.map(\.artist))).sorted()
    }

    private var albums: [String] {
        Array(Set(songs.map(\.album))).sorted()
    }

    private var genres: [String] {
        Array(Set(songs.map(\.genre).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("All Songs", systemImage: "music.note.list")
                    .tag(SidebarCategory.allSongs)
                    .dropDestination(for: URL.self) { urls, _ in
                        libraryManager.importURLs(urls, context: modelContext)
                        return true
                    }
            }

            if !artists.isEmpty {
                Section("Artists") {
                    ForEach(artists, id: \.self) { artist in
                        Label(artist, systemImage: "person")
                            .tag(SidebarCategory.artist(artist))
                    }
                }
            }

            if !albums.isEmpty {
                Section("Albums") {
                    ForEach(albums, id: \.self) { album in
                        Label(album, systemImage: "square.stack")
                            .tag(SidebarCategory.album(album))
                    }
                }
            }

            if !genres.isEmpty {
                Section("Genres") {
                    ForEach(genres, id: \.self) { genre in
                        Label(genre, systemImage: "guitars")
                            .tag(SidebarCategory.genre(genre))
                    }
                }
            }

            Section("Playlists") {
                ForEach(playlists) { playlist in
                    PlaylistRow(
                        playlist: playlist,
                        isEditing: editingPlaylistID == playlist.persistentModelID,
                        onCommit: { editingPlaylistID = nil }
                    )
                    .tag(SidebarCategory.playlist(playlist.persistentModelID))
                    .dropDestination(for: String.self) { strings, _ in
                        for string in strings {
                            guard let uuid = UUID(uuidString: string) else { continue }
                            addSongToPlaylist(songID: uuid, playlist: playlist)
                        }
                        return true
                    }
                    .dropDestination(for: URL.self) { urls, _ in
                        libraryManager.importURLsToPlaylist(
                            urls, playlist: playlist, context: modelContext
                        )
                        return true
                    }
                    .contextMenu {
                        Button("Rename") {
                            editingPlaylistID = playlist.persistentModelID
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            modelContext.delete(playlist)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    createPlaylist()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .help("New Playlist")
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func addSongToPlaylist(songID: UUID, playlist: Playlist) {
        guard let song = songs.first(where: { $0.id == songID }) else { return }
        let alreadyInPlaylist = playlist.entries.contains { $0.song?.id == songID }
        guard !alreadyInPlaylist else { return }
        let nextIndex = (playlist.entries.map(\.orderIndex).max() ?? -1) + 1
        let entry = PlaylistEntry(song: song, playlist: playlist, orderIndex: nextIndex)
        modelContext.insert(entry)
    }

    func createPlaylist() {
        let playlist = Playlist(name: "Untitled Playlist")
        modelContext.insert(playlist)
        selection = .playlist(playlist.persistentModelID)
        editingPlaylistID = playlist.persistentModelID
    }
}

// MARK: - Playlist Row

private struct PlaylistRow: View {
    @Bindable var playlist: Playlist
    var isEditing: Bool
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        if isEditing {
            TextField("Playlist Name", text: $playlist.name)
                .focused($isFocused)
                .onSubmit { onCommit() }
                .onAppear { isFocused = true }
        } else {
            Label(playlist.name, systemImage: "music.note.list")
        }
    }
}
