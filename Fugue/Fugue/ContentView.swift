import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PlaybackService.self) private var playbackService

    @State private var selectedCategory: SidebarCategory? = .allSongs
    @State private var selectedSongIDs: Set<UUID> = []
    @State private var sortOrder = [KeyPathComparator(\Song.title)]
    @State private var editingPlaylistID: PersistentIdentifier?
    @Environment(\.openWindow) private var openWindow
    @AppStorage("isVisualizationShown") private var isVisualizationShown = false
    @AppStorage("visualizationHeight") private var visualizationHeight: Double = 250
    @AppStorage("visibleColumns") private var visibleColumns = VisibleColumnSet(columns: SongColumn.defaultVisible)
    @State private var libraryFilter: LibraryFilter = .all
    @State private var browseSelection: String?
    @State private var isDetailVisible = true

    private var selectedPlaylist: Playlist? {
        if case .playlist(let id) = selectedCategory {
            return try? modelContext.model(for: id) as? Playlist
        }
        return nil
    }

    private var selectedSong: Song? {
        guard selectedSongIDs.count == 1, let id = selectedSongIDs.first else { return nil }
        let descriptor = FetchDescriptor<Song>(predicate: #Predicate<Song> { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(
                    selection: $selectedCategory,
                    editingPlaylistID: $editingPlaylistID
                )
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            } detail: {
                HStack(spacing: 0) {
                    if selectedCategory == .artists || selectedCategory == .albums {
                        BrowseListView(
                            isArtists: selectedCategory == .artists,
                            selection: $browseSelection
                        )
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300)
                        Divider()
                    }
                    QuerySongTableView(
                        category: selectedCategory,
                        filter: libraryFilter,
                        browseSelection: browseSelection,
                        visibleColumns: visibleColumns.columns,
                        playlist: selectedPlaylist,
                        selection: $selectedSongIDs,
                        sortOrder: $sortOrder
                    )
                }
                .toolbar {
                    ImportButton()
                    LibraryFilterMenu(
                        filter: $libraryFilter,
                        sortOrder: $sortOrder,
                        visibleColumns: $visibleColumns
                    )
                    Button {
                        withAnimation {
                            isDetailVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.trailing")
                    }
                    .help(isDetailVisible ? "Hide Details" : "Show Details")
                }
                .inspector(isPresented: $isDetailVisible) {
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
        .alert(
            "Import Complete",
            isPresented: Bindable(libraryManager).showImportSummaryAlert
        ) {
            Button("OK") {}
        } message: {
            Text(importSummaryMessage)
        }
        .onChange(of: selectedCategory) {
            browseSelection = nil
        }
    }

    private var importSummaryMessage: String {
        var lines: [String] = []
        let dupes = libraryManager.duplicatesRemoved
        let errors = libraryManager.importErrors
        if dupes > 0 {
            lines.append("\(dupes) duplicate file\(dupes == 1 ? " was" : "s were") skipped and moved to the Trash.")
        }
        if errors > 0 {
            lines.append("\(errors) file\(errors == 1 ? "" : "s") could not be imported.")
        }
        return lines.joined(separator: "\n")
    }

    private func createNewPlaylist() {
        let playlist = Playlist(name: "Untitled Playlist")
        modelContext.insert(playlist)
        selectedCategory = .playlist(playlist.persistentModelID)
        editingPlaylistID = playlist.persistentModelID
    }
}

// MARK: - Query-backed Song Table

/// Wraps SongTableView with a @Query that delegates filtering and sorting to SQLite,
/// avoiding Swift-side iteration that forces SwiftData to fault every Song object.
private struct QuerySongTableView: View {
    @Query private var queriedSongs: [Song]
    let playlist: Playlist?
    let filter: LibraryFilter
    let visibleColumns: Set<String>
    @State private var searchText = ""
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<Song>]

    init(
        category: SidebarCategory?,
        filter: LibraryFilter,
        browseSelection: String?,
        visibleColumns: Set<String>,
        playlist: Playlist?,
        selection: Binding<Set<UUID>>,
        sortOrder: Binding<[KeyPathComparator<Song>]>
    ) {
        self.playlist = playlist
        self.filter = filter
        self.visibleColumns = visibleColumns
        self._selection = selection
        self._sortOrder = sortOrder

        let predicate = Self.makePredicate(category: category, filter: filter, browseSelection: browseSelection)
        let descriptors = Self.makeSortDescriptors(from: sortOrder.wrappedValue)

        var descriptor = FetchDescriptor<Song>(predicate: predicate, sortBy: descriptors)
        descriptor.propertiesToFetch = [
            \.id, \.title, \.artist, \.album, \.genre,
            \.duration, \.tempo, \.trackCount, \.relativePath,
            \.isFavorite, \.lastPlayed, \.playCount, \.dateAdded
        ]
        _queriedSongs = Query(descriptor)
    }

    private var displayedSongs: [Song] {
        if let playlist {
            let ordered = playlist.orderedSongs
            if searchText.isEmpty { return ordered }
            return ordered.filter { song in
                song.title.localizedCaseInsensitiveContains(searchText)
                || song.artist.localizedCaseInsensitiveContains(searchText)
                || song.album.localizedCaseInsensitiveContains(searchText)
            }
        }
        if searchText.isEmpty { return queriedSongs }
        return queriedSongs.filter { song in
            song.title.localizedCaseInsensitiveContains(searchText)
            || song.artist.localizedCaseInsensitiveContains(searchText)
            || song.album.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        SongTableView(
            songs: displayedSongs,
            playlist: playlist,
            visibleColumns: visibleColumns,
            selection: $selection,
            sortOrder: $sortOrder
        )
        .searchable(text: $searchText, prompt: "Search songs")
    }

    // MARK: - Predicate Builder

    /// Category + filter + browse predicate. Search filtering is done in Swift on
    /// already-faulted objects so that changing/clearing the search text doesn't recreate the @Query.
    private static func makePredicate(
        category: SidebarCategory?,
        filter: LibraryFilter,
        browseSelection: String?
    ) -> Predicate<Song>? {
        switch category {
        case .favorites:
            return #Predicate<Song> { song in song.isFavorite == true }
        case .none, .allSongs, .playlist:
            switch filter {
            case .all: return nil
            case .favorites: return #Predicate<Song> { song in song.isFavorite == true }
            }
        case .artists:
            if let name = browseSelection {
                switch filter {
                case .all:
                    return #Predicate<Song> { song in song.artist == name }
                case .favorites:
                    return #Predicate<Song> { song in song.artist == name && song.isFavorite == true }
                }
            } else {
                switch filter {
                case .all: return nil
                case .favorites: return #Predicate<Song> { song in song.isFavorite == true }
                }
            }
        case .albums:
            if let name = browseSelection {
                switch filter {
                case .all:
                    return #Predicate<Song> { song in song.album == name }
                case .favorites:
                    return #Predicate<Song> { song in song.album == name && song.isFavorite == true }
                }
            } else {
                switch filter {
                case .all: return nil
                case .favorites: return #Predicate<Song> { song in song.isFavorite == true }
                }
            }
        case .genre(let name):
            switch filter {
            case .all:
                return #Predicate<Song> { song in song.genre == name }
            case .favorites:
                return #Predicate<Song> { song in song.genre == name && song.isFavorite == true }
            }
        }
    }

    // MARK: - Sort Descriptor Mapping

    /// Maps Table KeyPathComparators to Query SortDescriptors by matching against known columns.
    private static func makeSortDescriptors(from comparators: [KeyPathComparator<Song>]) -> [SortDescriptor<Song>] {
        let result: [SortDescriptor<Song>] = comparators.compactMap { comp in
            let order = comp.order

            // String columns
            for kp in [\Song.title, \Song.artist, \Song.album, \Song.genre] as [KeyPath<Song, String>] {
                if comp == KeyPathComparator<Song>(kp, order: order) {
                    return SortDescriptor(kp, order: order)
                }
            }

            // Double columns
            for kp in [\Song.duration, \Song.tempo] as [KeyPath<Song, Double>] {
                if comp == KeyPathComparator<Song>(kp, order: order) {
                    return SortDescriptor(kp, order: order)
                }
            }

            // Int columns
            for kp in [\Song.trackCount, \Song.playCount] as [KeyPath<Song, Int>] {
                if comp == KeyPathComparator<Song>(kp, order: order) {
                    return SortDescriptor(kp, order: order)
                }
            }

            // Date columns
            if comp == KeyPathComparator<Song>(\Song.dateAdded, order: order) {
                return SortDescriptor(\Song.dateAdded, order: order)
            }

            // Optional Date columns
            if comp == KeyPathComparator<Song>(\Song.lastPlayed, order: order) {
                return SortDescriptor(\Song.lastPlayed, order: order)
            }

            return nil
        }

        // Fallback to title sort if mapping failed
        return result.isEmpty ? [SortDescriptor(\Song.title)] : result
    }
}

// MARK: - Browse List (Artists / Albums sub-list)

private struct BrowseListView: View {
    @Query private var songs: [Song]
    let isArtists: Bool
    @Binding var selection: String?

    init(isArtists: Bool, selection: Binding<String?>) {
        self.isArtists = isArtists
        self._selection = selection
        var descriptor = FetchDescriptor<Song>(sortBy: [SortDescriptor(\Song.artist)])
        descriptor.propertiesToFetch = [\.artist, \.album]
        _songs = Query(descriptor)
    }

    private var items: [String] {
        let values = isArtists ? songs.map(\.artist) : songs.map(\.album)
        return Array(Set(values)).sorted()
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(items, id: \.self) { item in
                Text(item)
            }
        }
        .listStyle(.inset)
    }
}
