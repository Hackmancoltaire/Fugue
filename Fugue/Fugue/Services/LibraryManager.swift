import CryptoKit
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
    var isImporting = false
    var importTotal = 0
    var importCompleted = 0
    var duplicatesRemoved = 0
    var importErrors = 0
    var showImportSummaryAlert = false
    private var importTask: Task<Void, Never>?

    var isLibraryAccessGranted: Bool {
        libraryURL != nil
    }

    var importProgress: Double {
        guard importTotal > 0 else { return 0 }
        return Double(importCompleted) / Double(importTotal)
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

    func cancelImport() {
        importTask?.cancel()
    }

    func importMIDIFilesAsync(urls: [URL], context: ModelContext, playlist: Playlist? = nil) {
        guard !isImporting else { return }
        isImporting = true
        importTotal = urls.count
        importCompleted = 0
        duplicatesRemoved = 0

        var nextPlaylistIndex = playlist.map { ($0.entries.map(\.orderIndex).max() ?? -1) + 1 } ?? 0

        importTask = Task {
            var duplicateCount = 0
            var errorCount = 0

            for url in urls {
                if Task.isCancelled { break }

                _ = url.startAccessingSecurityScopedResource()

                do {
                    let prep = try await prepareFileForImportAsync(from: url)
                    url.stopAccessingSecurityScopedResource()

                    if Task.isCancelled { break }

                    // Check for duplicate by MD5 hash
                    if isDuplicateHash(prep.md5Hash, context: context) {
                        // Trash the file that was already copied/moved to library
                        if let libraryURL {
                            let destURL = libraryURL.appendingPathComponent(prep.relativePath)
                            NSWorkspace.shared.recycle([destURL]) { _, _ in }
                            cleanEmptyDirectories(
                                from: destURL.deletingLastPathComponent(), stopAt: libraryURL
                            )
                        }
                        duplicateCount += 1
                    } else {
                        let song = insertSong(from: prep, context: context)
                        if let playlist {
                            let entry = PlaylistEntry(song: song, playlist: playlist, orderIndex: nextPlaylistIndex)
                            context.insert(entry)
                            nextPlaylistIndex += 1
                        }
                    }
                } catch {
                    url.stopAccessingSecurityScopedResource()
                    errorCount += 1
                    print("Import error: \(error)")
                }

                importCompleted += 1
            }

            isImporting = false
            importTask = nil
            duplicatesRemoved = duplicateCount
            importErrors = errorCount
            if duplicateCount > 0 || errorCount > 0 {
                showImportSummaryAlert = true
            }
        }
    }

    func importURLs(_ urls: [URL], context: ModelContext) {
        let midiURLs = resolveMIDIFiles(from: urls)
        guard !midiURLs.isEmpty else { return }
        importMIDIFilesAsync(urls: midiURLs, context: context)
    }

    func importURLsToPlaylist(_ urls: [URL], playlist: Playlist, context: ModelContext) {
        let midiURLs = resolveMIDIFiles(from: urls)
        guard !midiURLs.isEmpty else { return }
        importMIDIFilesAsync(urls: midiURLs, context: context, playlist: playlist)
    }

    /// Expands URLs into a flat list of MIDI files, recursively enumerating directories.
    private func resolveMIDIFiles(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                guard let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                while let fileURL = enumerator.nextObject() as? URL {
                    if ["mid", "midi"].contains(fileURL.pathExtension.lowercased()) {
                        result.append(fileURL)
                    }
                }
            } else if ["mid", "midi"].contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result
    }

    @discardableResult
    func importMIDIFile(from sourceURL: URL, context: ModelContext) throws -> Song {
        let prep = try prepareFileForImport(from: sourceURL)
        return insertSong(from: prep, context: context)
    }

    private struct ImportPreparation {
        let metadata: MIDIMetadata
        let relativePath: String
        let sourceFilename: String
        let md5Hash: String
    }

    private func prepareFileForImportAsync(from sourceURL: URL) async throws -> ImportPreparation {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.prepareFileForImport(from: sourceURL)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func prepareFileForImport(from sourceURL: URL) throws -> ImportPreparation {
        guard let libraryURL else { throw LibraryError.noLibraryAccess }

        let sourceData = try Data(contentsOf: sourceURL)
        let md5Hash = Insecure.MD5.hash(data: sourceData)
            .map { String(format: "%02x", $0) }
            .joined()

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
                try FileManager.default.copyItem(at: sourceURL, to: destURL)
            }
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        }

        let relativePath = destURL.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
        let sourceFilename = sourceURL.deletingPathExtension().lastPathComponent

        return ImportPreparation(metadata: metadata, relativePath: relativePath, sourceFilename: sourceFilename, md5Hash: md5Hash)
    }

    private func insertSong(from prep: ImportPreparation, context: ModelContext) -> Song {
        let title = prep.metadata.title.isEmpty ? prep.sourceFilename : prep.metadata.title
        let artist = prep.metadata.artist.isEmpty ? "Unknown Artist" : prep.metadata.artist
        let album = prep.metadata.album.isEmpty ? "Unknown Album" : prep.metadata.album

        let song = Song(title: title, artist: artist, album: album, relativePath: prep.relativePath)
        song.genre = prep.metadata.genre
        song.duration = prep.metadata.duration
        song.tempo = prep.metadata.tempo
        song.timeSignatureNumerator = prep.metadata.timeSignatureNumerator
        song.timeSignatureDenominator = prep.metadata.timeSignatureDenominator
        song.trackCount = prep.metadata.trackCount
        song.fileFormat = prep.metadata.fileFormat
        song.ticksPerQuarterNote = prep.metadata.ticksPerQuarterNote
        song.instruments = prep.metadata.instruments
        song.channelInstruments = prep.metadata.channelInstruments
            .sorted { $0.key < $1.key }
            .map { ChannelInstrument(channel: $0.key, name: $0.value) }
        song.trackInfos = prep.metadata.trackInfos
        song.fileSize = prep.metadata.fileSize
        song.md5Hash = prep.md5Hash

        context.insert(song)
        return song
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

    private func isDuplicateHash(_ hash: String, context: ModelContext) -> Bool {
        guard !hash.isEmpty else { return false }
        let descriptor = FetchDescriptor<Song>(
            predicate: #Predicate<Song> { $0.md5Hash == hash }
        )
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
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
