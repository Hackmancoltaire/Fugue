import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SongTableView: View {
    var songs: [Song]
    var playlist: Playlist?
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<Song>]
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Table(of: Song.self, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { song in
                @Bindable var song = song
                TextField("", text: $song.title)
                    .textFieldStyle(.plain)
                    .onSubmit { song.dateModified = Date() }
            }
            TableColumn("Artist", value: \.artist) { song in
                @Bindable var song = song
                TextField("", text: $song.artist)
                    .textFieldStyle(.plain)
                    .onSubmit { libraryManager.reorganizeSong(song) }
            }
            TableColumn("Album", value: \.album) { song in
                @Bindable var song = song
                TextField("", text: $song.album)
                    .textFieldStyle(.plain)
                    .onSubmit { libraryManager.reorganizeSong(song) }
            }
            TableColumn("Genre", value: \.genre) { song in
                @Bindable var song = song
                TextField("", text: $song.genre)
                    .textFieldStyle(.plain)
                    .onSubmit { song.dateModified = Date() }
            }
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
            if playlist != nil {
                ForEach(songs) { song in
                    TableRow(song)
                        .draggable(song.id.uuidString)
                }
                .onInsert(of: [.plainText]) { index, providers in
                    handleReorder(at: index, providers: providers)
                }
            } else {
                ForEach(songs) { song in
                    TableRow(song)
                        .draggable(song.id.uuidString)
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let playlist {
                libraryManager.importURLsToPlaylist(urls, playlist: playlist, context: modelContext)
            } else {
                libraryManager.importURLs(urls, context: modelContext)
            }
            return true
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if songFor(ids) != nil {
                Button("Play") {
                    if let song = songFor(ids) { playSong(song) }
                }
                Divider()
                if playlist != nil {
                    Button("Remove from Playlist") {
                        removeSelectedFromPlaylist()
                    }
                    Button("Delete from Library", role: .destructive) {
                        deleteSelectedFromLibrary()
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        deleteSelectedFromLibrary()
                    }
                }
            }
        } primaryAction: { ids in
            if let song = songFor(ids) {
                playSong(song)
            }
        }
        .onDeleteCommand {
            if playlist != nil {
                removeSelectedFromPlaylist()
            } else {
                deleteSelectedFromLibrary()
            }
        }
    }

    // MARK: - Helpers

    private func songFor(_ ids: Set<UUID>) -> Song? {
        guard let id = ids.first else { return nil }
        return songs.first { $0.id == id }
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
