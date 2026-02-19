import Foundation
import SwiftData

@Model
final class Playlist {
    var name: String = ""
    var dateCreated: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
    var entries: [PlaylistEntry] = []

    var orderedSongs: [Song] {
        entries.sorted { $0.orderIndex < $1.orderIndex }.compactMap(\.song)
    }

    init(name: String) {
        self.name = name
        self.dateCreated = Date()
    }
}
