import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SongTableView: View {
    var songs: [Song]
    var playlist: Playlist?
    var visibleColumns: Set<String>
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<Song>]
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if playlist != nil {
            playlistTable
        } else {
            libraryTable
        }
    }

    // MARK: - Library Table (native NSTableView for smooth scrolling)

    private var libraryTable: some View {
        NativeSongTableView(
            songs: songs,
            visibleColumns: visibleColumns,
            selection: $selection,
            sortOrder: $sortOrder,
            onPlay: { playSong($0) },
            onDelete: { deleteSelectedFromLibrary() },
            onDrop: { urls in libraryManager.importURLs(urls, context: modelContext) },
            onToggleFavorite: { $0.isFavorite.toggle() },
            onShowInFinder: { showInFinder($0) },
            onSpacebar: { song in handleSpacebar(song) }
        )
    }

    // MARK: - Playlist Table (ForEach-based, supports drag reordering)

    private var playlistTable: some View {
        Table(of: Song.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("♥", value: \.title) { song in
                Button {
                    song.isFavorite.toggle()
                } label: {
                    Image(systemName: song.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(song.isFavorite ? Color.yellow : Color.gray.opacity(0.3))
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
            .width(32)
            TableColumn("Title", value: \.title)
            TableColumn("Artist", value: \.artist)
            TableColumn("Album", value: \.album)
            TableColumn("Genre", value: \.genre)
                .width(min: 60, ideal: 100)
            TableColumn("Duration", value: \.duration) { song in
                Text(song.formattedDuration)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Tempo", value: \.tempo) { song in
                Text("\(Int(song.tempo)) BPM")
            }
            .width(min: 70, ideal: 90)
            TableColumn("Tracks", value: \.trackCount) { song in
                Text("\(song.trackCount)")
            }
            .width(min: 50, ideal: 60)
        } rows: {
            ForEach(songs) { song in
                TableRow(song)
                    .draggable(song.id.uuidString)
            }
            .onInsert(of: [.plainText]) { index, providers in
                handleReorder(at: index, providers: providers)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let playlist {
                libraryManager.importURLsToPlaylist(urls, playlist: playlist, context: modelContext)
            }
            return true
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if songFor(ids) != nil {
                Button("Play") {
                    if let song = songFor(ids) { playSong(song) }
                }
                Divider()
                Button("Show in Finder") {
                    if let song = songFor(ids) { showInFinder(song) }
                }
                Divider()
                Button("Remove from Playlist") {
                    removeSelectedFromPlaylist()
                }
                Button("Delete from Library", role: .destructive) {
                    deleteSelectedFromLibrary()
                }
            }
        } primaryAction: { ids in
            if let song = songFor(ids) {
                playSong(song)
            }
        }
        .onDeleteCommand {
            removeSelectedFromPlaylist()
        }
    }

    // MARK: - Helpers

    private func songFor(_ ids: Set<UUID>) -> Song? {
        guard let id = ids.first else { return nil }
        return songs.first { $0.id == id }
    }

    private func showInFinder(_ song: Song) {
        guard let url = libraryManager.resolveURL(for: song) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func handleSpacebar(_ song: Song?) {
        if let song, song.id != playbackService.currentSong?.id {
            playSong(song)
        } else {
            playbackService.togglePlayPause()
        }
    }

    private func playSong(_ song: Song) {
        guard let url = libraryManager.resolveURL(for: song) else { return }
        playbackService.play(song, url: url)
    }

    private func removeSelectedFromPlaylist() {
        guard let playlist else { return }
        for songID in selection {
            if let entry = playlist.entries.first(where: { $0.song?.id == songID }) {
                modelContext.delete(entry)
            }
        }
    }

    private func deleteSelectedFromLibrary() {
        for songID in selection {
            if let song = songs.first(where: { $0.id == songID }) {
                libraryManager.deleteSong(song, context: modelContext)
            }
        }
        selection.removeAll()
    }

    private func handleReorder(at index: Int, providers: [NSItemProvider]) {
        guard let playlist else { return }
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { string, _ in
                guard let uuidString = string as? String,
                      let songID = UUID(uuidString: uuidString) else { return }
                Task { @MainActor in
                    reorderPlaylistSong(songID: songID, toIndex: index, in: playlist)
                }
            }
        }
    }

    private func reorderPlaylistSong(songID: UUID, toIndex destination: Int, in playlist: Playlist) {
        var songIDs = songs.map(\.id)
        guard let sourceIndex = songIDs.firstIndex(of: songID) else { return }
        songIDs.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        for (index, id) in songIDs.enumerated() {
            if let entry = playlist.entries.first(where: { $0.song?.id == id }) {
                entry.orderIndex = index
            }
        }
    }
}
