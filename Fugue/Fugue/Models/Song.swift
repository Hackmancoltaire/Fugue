import Foundation
import SwiftData

struct ChannelInstrument: Codable, Hashable {
    let channel: Int
    let name: String
}

struct TrackInfo: Codable, Hashable {
    let index: Int
    let name: String
    /// MIDI channel this track primarily uses, or nil for meta-only tracks.
    let channel: Int?
    let hasNotes: Bool
}

@Model
final class Song {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var artist: String = "Unknown Artist"
    var album: String = "Unknown Album"
    var genre: String = ""
    var duration: TimeInterval = 0
    var tempo: Double = 120
    var timeSignatureNumerator: Int = 4
    var timeSignatureDenominator: Int = 4
    var trackCount: Int = 0
    var fileFormat: Int = 0
    var ticksPerQuarterNote: Int = 480
    var instruments: [String] = []
    var channelInstruments: [ChannelInstrument] = []
    var trackInfos: [TrackInfo] = []
    var mutedChannels: [Int] = []
    var playCount: Int = 0
    var isFavorite: Bool = false
    var lastPlayed: Date?
    var relativePath: String = ""
    var md5Hash: String = ""
    var fileSize: Int64 = 0
    var dateAdded: Date = Date()
    var dateModified: Date = Date()

    var playlistEntries: [PlaylistEntry] = []

    init(title: String, artist: String, album: String, relativePath: String) {
        self.id = UUID()
        self.title = title
        self.artist = artist
        self.album = album
        self.relativePath = relativePath
        self.dateAdded = Date()
        self.dateModified = Date()
    }
}
