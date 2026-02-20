import SwiftUI
import SwiftData

enum SidebarCategory: Hashable {
    case allSongs
    case favorites
    case artists
    case albums
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
                Label("Favorites", systemImage: "star.fill")
                    .tag(SidebarCategory.favorites)
                Label("Artists", systemImage: "music.mic")
                    .tag(SidebarCategory.artists)
                Label("Albums", systemImage: "square.stack")
                    .tag(SidebarCategory.albums)
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
            VStack(spacing: 0) {
                if libraryManager.isImporting {
                    Divider()
                    HStack(spacing: 8) {
                        ProgressView(value: libraryManager.importProgress)

                        Text("\(libraryManager.importCompleted)/\(libraryManager.importTotal)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)

                        Button {
                            libraryManager.cancelImport()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Cancel Import")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }

                Divider()

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
