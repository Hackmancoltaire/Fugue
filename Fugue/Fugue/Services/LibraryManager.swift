import Foundation
import SwiftData
import AppKit

enum ImportMode: String, CaseIterable {
    case move
    case copy

    var label: String {
        switch self {
        case .move: return "Move to Library"
        case .copy: return "Copy to Library"
        }
    }
}

@Observable
class LibraryManager {
    var libraryURL: URL?

    var isLibraryAccessGranted: Bool {
        libraryURL != nil
    }

    private let bookmarkKey = "FugueLibraryBookmark"

    init() {
        restoreBookmark()
    }

    // MARK: - Library Access

    func requestLibraryAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Library Folder"
        panel.message = "Select or create a folder for your Fugue MIDI library"

        let musicDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music")
            .appendingPathComponent("Fugue")
        try? FileManager.default.createDirectory(at: musicDir, withIntermediateDirectories: true)
        panel.directoryURL = musicDir

        if panel.runModal() == .OK, let url = panel.url {
            saveBookmark(for: url)
            libraryURL = url
        }
    }

    // MARK: - Import

    @discardableResult
    func importMIDIFile(from sourceURL: URL, context: ModelContext) throws -> Song {
        guard let libraryURL else {
            throw LibraryError.noLibraryAccess
        }

        let metadata = try MIDIMetadataExtractor.extract(from: sourceURL)

        let artist = metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist
        let album = metadata.album.isEmpty ? "Unknown Album" : metadata.album

        let destDir = libraryURL
            .appendingPathComponent(sanitizeFilename(artist))
            .appendingPathComponent(sanitizeFilename(album))

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        var destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension
            destURL = destDir.appendingPathComponent("\(stem) \(counter).\(ext)")
            counter += 1
        }

        let importMode = ImportMode(
            rawValue: UserDefaults.standard.string(forKey: "importMode") ?? ImportMode.move.rawValue
        ) ?? .move

        if importMode == .move {
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destURL)
            } catch {
                // Fall back to copy (e.g., cross-volume or read-only source)
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        let relativePath = destURL.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
        let title = metadata.title.isEmpty
            ? sourceURL.deletingPathExtension().lastPathComponent
            : metadata.title

        let song = Song(title: title, artist: artist, album: album, relativePath: relativePath)
        song.genre = metadata.genre
        song.duration = metadata.duration
        song.tempo = metadata.tempo
        song.timeSignatureNumerator = metadata.timeSignatureNumerator
        song.timeSignatureDenominator = metadata.timeSignatureDenominator
        song.trackCount = metadata.trackCount
        song.fileFormat = metadata.fileFormat
        song.ticksPerQuarterNote = metadata.ticksPerQuarterNote
        song.instruments = metadata.instruments
        song.channelInstruments = metadata.channelInstruments
            .sorted { $0.key < $1.key }
            .map { ChannelInstrument(channel: $0.key, name: $0.value) }
        song.trackInfos = metadata.trackInfos
        song.fileSize = metadata.fileSize

        context.insert(song)
        return song
    }

    func importURLs(_ urls: [URL], context: ModelContext) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "mid" || ext == "midi" else { continue }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                try importMIDIFile(from: url, context: context)
            } catch {
                print("Import error: \(error)")
            }
        }
    }

    func importURLsToPlaylist(_ urls: [URL], playlist: Playlist, context: ModelContext) {
        var nextIndex = (playlist.entries.map(\.orderIndex).max() ?? -1) + 1
        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard ext == "mid" || ext == "midi" else { continue }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let song = try importMIDIFile(from: url, context: context)
                let entry = PlaylistEntry(song: song, playlist: playlist, orderIndex: nextIndex)
                context.insert(entry)
                nextIndex += 1
            } catch {
                print("Import error: \(error)")
            }
        }
    }

    // MARK: - Scan

    func scanLibrary(context: ModelContext) throws {
        guard let libraryURL else {
            throw LibraryError.noLibraryAccess
        }

        guard let enumerator = FileManager.default.enumerator(
            at: libraryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            let ext = fileURL.pathExtension.lowercased()
            guard ext == "mid" || ext == "midi" else { continue }

            let path = fileURL.path.replacingOccurrences(
                of: libraryURL.path + "/",
                with: ""
            )

            let descriptor = FetchDescriptor<Song>(
                predicate: #Predicate { $0.relativePath == path }
            )
            let existing = try context.fetch(descriptor)
            guard existing.isEmpty else { continue }

            let metadata = try MIDIMetadataExtractor.extract(from: fileURL)
            let title = metadata.title.isEmpty
                ? fileURL.deletingPathExtension().lastPathComponent
                : metadata.title
            let artist = metadata.artist.isEmpty ? "Unknown Artist" : metadata.artist
            let album = metadata.album.isEmpty ? "Unknown Album" : metadata.album

            let song = Song(title: title, artist: artist, album: album, relativePath: path)
            song.genre = metadata.genre
            song.duration = metadata.duration
            song.tempo = metadata.tempo
            song.timeSignatureNumerator = metadata.timeSignatureNumerator
            song.timeSignatureDenominator = metadata.timeSignatureDenominator
            song.trackCount = metadata.trackCount
            song.fileFormat = metadata.fileFormat
            song.ticksPerQuarterNote = metadata.ticksPerQuarterNote
            song.instruments = metadata.instruments
            song.channelInstruments = metadata.channelInstruments
                .sorted { $0.key < $1.key }
                .map { ChannelInstrument(channel: $0.key, name: $0.value) }
            song.trackInfos = metadata.trackInfos
            song.fileSize = metadata.fileSize

            context.insert(song)
        }
    }

    // MARK: - Reorganize

    func reorganizeSong(_ song: Song) {
        guard let libraryURL else { return }

        let oldURL = libraryURL.appendingPathComponent(song.relativePath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else { return }

        let filename = oldURL.lastPathComponent
        let newDir = libraryURL
            .appendingPathComponent(sanitizeFilename(song.artist))
            .appendingPathComponent(sanitizeFilename(song.album))
        let newURL = newDir.appendingPathComponent(filename)

        guard oldURL.path != newURL.path else { return }

        do {
            try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            song.relativePath = newURL.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
            song.dateModified = Date()

            cleanEmptyDirectories(from: oldURL.deletingLastPathComponent(), stopAt: libraryURL)
        } catch {
            print("Failed to reorganize: \(error)")
        }
    }

    // MARK: - Resolve & Delete

    func resolveURL(for song: Song) -> URL? {
        guard let libraryURL else { return nil }
        return libraryURL.appendingPathComponent(song.relativePath)
    }

    func deleteSong(_ song: Song, context: ModelContext) {
        if let url = resolveURL(for: song) {
            NSWorkspace.shared.recycle([url]) { _, _ in }
        }
        context.delete(song)
    }

    // MARK: - Private

    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveBookmark(for: url)
            }
            if url.startAccessingSecurityScopedResource() {
                libraryURL = url
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
    }

    private func cleanEmptyDirectories(from dir: URL, stopAt root: URL) {
        var current = dir
        while current.path != root.path, current.path.hasPrefix(root.path) {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  contents.isEmpty else { break }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
}

enum LibraryError: LocalizedError {
    case noLibraryAccess

    var errorDescription: String? {
        switch self {
        case .noLibraryAccess:
            return "No library folder access. Please select a library folder."
        }
    }
}
