import Foundation

enum SongColumn: String, CaseIterable, Identifiable {
    case favorite
    case title
    case artist
    case album
    case genre
    case duration
    case tempo
    case tracks
    case playCount
    case dateAdded
    case lastPlayed

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .favorite:  return "♥"
        case .title:     return "Title"
        case .artist:    return "Artist"
        case .album:     return "Album"
        case .genre:     return "Genre"
        case .duration:  return "Duration"
        case .tempo:     return "Tempo"
        case .tracks:    return "Tracks"
        case .playCount: return "Play Count"
        case .dateAdded: return "Date Added"
        case .lastPlayed: return "Last Played"
        }
    }

    var minWidth: CGFloat? {
        switch self {
        case .favorite:   return 28
        case .genre:      return 60
        case .duration:   return 60
        case .tempo:      return 70
        case .tracks:     return 50
        case .playCount:  return 50
        case .dateAdded:  return 80
        case .lastPlayed: return 80
        default:          return nil
        }
    }

    var defaultWidth: CGFloat? {
        switch self {
        case .favorite:   return 32
        case .genre:      return 100
        case .duration:   return 80
        case .tempo:      return 90
        case .tracks:     return 60
        case .playCount:  return 70
        case .dateAdded:  return 110
        case .lastPlayed: return 130
        default:          return nil
        }
    }

    var isSortable: Bool {
        self != .favorite
    }

    static let defaultVisible: Set<String> = [
        "favorite", "title", "artist", "album", "genre", "duration", "tempo", "tracks"
    ]

    static let alwaysVisible: Set<String> = ["title"]
}

// MARK: - VisibleColumnSet (@AppStorage wrapper)

struct VisibleColumnSet: RawRepresentable {
    var columns: Set<String>

    init(columns: Set<String>) {
        self.columns = columns
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        self.columns = Set(array)
    }

    var rawValue: String {
        let array = columns.sorted()
        guard let data = try? JSONEncoder().encode(array),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
