import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PlaybackService.self) private var playbackService
    @Query(sort: \Song.title) private var songs: [Song]

    @State private var selectedCategory: SidebarCategory? = .allSongs
    @State private var selectedSongIDs: Set<UUID> = []
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Song.title)]
    @State private var editingPlaylistID: PersistentIdentifier?
    @Environment(\.openWindow) private var openWindow
    @AppStorage("isVisualizationShown") private var isVisualizationShown = false
    @AppStorage("visualizationHeight") private var visualizationHeight: Double = 250

    private var filteredSongs: [Song] {
        // Playlist mode: preserve orderIndex ordering, only apply search filter
        if case .playlist(let id) = selectedCategory,
           let playlist = try? modelContext.model(for: id) as? Playlist {
            let ordered = playlist.orderedSongs
            guard !searchText.isEmpty else { return ordered }
            return ordered.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText)
                || song.artist.localizedCaseInsensitiveContains(searchText)
                || song.album.localizedCaseInsensitiveContains(searchText)
            }
        }

        return songs.filter { song in
            let matchesCategory: Bool
            switch selectedCategory {
            case .none, .allSongs:
                matchesCategory = true
            case .artist(let name):
                matchesCategory = song.artist == name
            case .album(let name):
                matchesCategory = song.album == name
            case .genre(let name):
                matchesCategory = song.genre == name
            case .playlist:
                matchesCategory = false
            }

            let matchesSearch = searchText.isEmpty
                || song.title.localizedCaseInsensitiveContains(searchText)
                || song.artist.localizedCaseInsensitiveContains(searchText)
                || song.album.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
        .sorted(using: sortOrder)
    }

    private var selectedPlaylist: Playlist? {
        if case .playlist(let id) = selectedCategory {
            return try? modelContext.model(for: id) as? Playlist
        }
        return nil
    }

    private var selectedSong: Song? {
        guard selectedSongIDs.count == 1, let id = selectedSongIDs.first else { return nil }
        return songs.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(
                    selection: $selectedCategory,
                    editingPlaylistID: $editingPlaylistID
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            } content: {
                SongTableView(
                    songs: filteredSongs,
                    playlist: selectedPlaylist,
                    selection: $selectedSongIDs,
                    sortOrder: $sortOrder
                )
                .searchable(text: $searchText, prompt: "Search songs")
                .toolbar {
                    ImportButton()
                }
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            } detail: {
                if let selectedSong {
                    SongDetailView(song: selectedSong)
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "music.note",
                        description: Text("Select a song to view its details")
                    )
                }
            }

            if isVisualizationShown && playbackService.currentSong != nil {
                VisualizationDragHandle(height: $visualizationHeight)
                NoteVisualizationView()
                    .frame(height: visualizationHeight)
                    .clipped()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            TransportBar()
        }
        .focusedSceneValue(\.createPlaylist, createNewPlaylist)
        .focusedSceneValue(\.openVisualization) {
            openWindow(id: "note-visualization")
        }
        .onAppear {
            if !libraryManager.isLibraryAccessGranted {
                libraryManager.requestLibraryAccess()
            }
        }
    }

    private func createNewPlaylist() {
        let playlist = Playlist(name: "Untitled Playlist")
        modelContext.insert(playlist)
        selectedCategory = .playlist(playlist.persistentModelID)
        editingPlaylistID = playlist.persistentModelID
    }
}
