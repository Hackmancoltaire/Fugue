import Foundation
import SwiftData

@Model
final class PlaylistEntry {
    var orderIndex: Int = 0
    var song: Song?
    var playlist: Playlist?

    init(song: Song, playlist: Playlist, orderIndex: Int) {
        self.song = song
        self.playlist = playlist
        self.orderIndex = orderIndex
    }
}
