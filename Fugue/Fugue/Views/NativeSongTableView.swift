import SwiftUI

/// NSTableView-backed song list for butter-smooth scrolling.
/// Bypasses SwiftUI's per-cell NSHostingView bridging and @Observable tracking overhead.
struct NativeSongTableView: NSViewRepresentable {
    var songs: [Song]
    var visibleColumns: Set<String>
    @Binding var selection: Set<UUID>
    @Binding var sortOrder: [KeyPathComparator<Song>]
    var onPlay: (Song) -> Void
    var onDelete: () -> Void
    var onDrop: ([URL]) -> Void
    var onToggleFavorite: (Song) -> Void
    var onShowInFinder: (Song) -> Void
    var onSpacebar: (Song?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = KeyHandlingTableView()
        tableView.coordinator = context.coordinator
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        for col in SongColumn.allCases where visibleColumns.contains(col.rawValue) {
            tableView.addTableColumn(makeNSColumn(col))
        }

        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClick(_:))

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        tableView.registerForDraggedTypes([.fileURL])

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        context.coordinator.tableView = tableView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self

        c.syncColumns(visibleColumns: visibleColumns)

        let newIDs = songs.map(\.id)
        if c.songIDs != newIDs {
            c.songs = songs
            c.songIDs = newIDs
            c.isUpdatingSelection = true
            c.tableView?.reloadData()
            c.isUpdatingSelection = false
        }
        c.syncSelection()
        c.syncSortDescriptors()
    }

    private func makeNSColumn(_ col: SongColumn) -> NSTableColumn {
        let nsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.rawValue))
        nsCol.title = col.displayTitle
        if col.isSortable {
            nsCol.sortDescriptorPrototype = NSSortDescriptor(key: col.rawValue, ascending: true)
        }
        if let m = col.minWidth { nsCol.minWidth = m }
        if let w = col.defaultWidth { nsCol.width = w }
        if col == .favorite {
            nsCol.maxWidth = 32
        }
        return nsCol
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: NativeSongTableView
        var songs: [Song] = []
        var songIDs: [UUID] = []
        weak var tableView: NSTableView?
        var isUpdatingSelection = false
        private var isUpdatingSortOrder = false

        init(parent: NativeSongTableView) { self.parent = parent }

        // MARK: Column Sync

        func syncColumns(visibleColumns: Set<String>) {
            guard let tableView else { return }
            let currentIDs = Set(tableView.tableColumns.map(\.identifier.rawValue))
            let desired = visibleColumns

            // Remove columns no longer visible
            for col in tableView.tableColumns where !desired.contains(col.identifier.rawValue) {
                tableView.removeTableColumn(col)
            }

            // Add missing columns and ensure correct order
            let orderedCols = SongColumn.allCases.filter { desired.contains($0.rawValue) }
            for (targetIndex, songCol) in orderedCols.enumerated() {
                let colID = songCol.rawValue
                if !currentIDs.contains(colID) {
                    let nsCol = parent.makeNSColumn(songCol)
                    tableView.addTableColumn(nsCol)
                }
                // Reorder to correct position
                if let colIndex = tableView.tableColumns.firstIndex(where: { $0.identifier.rawValue == colID }),
                   colIndex != targetIndex, targetIndex < tableView.tableColumns.count {
                    tableView.moveColumn(colIndex, toColumn: targetIndex)
                }
            }
        }

        // MARK: Data Source

        func numberOfRows(in tableView: NSTableView) -> Int { songs.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, row < songs.count else { return nil }
            let id = column.identifier
            let song = songs[row]

            // Favorite column — star button
            if id.rawValue == "favorite" {
                let reuseID = NSUserInterfaceItemIdentifier("favoriteButton")
                let button: NSButton
                if let reused = tableView.makeView(withIdentifier: reuseID, owner: nil) as? NSButton {
                    button = reused
                } else {
                    button = NSButton(frame: .zero)
                    button.identifier = reuseID
                    button.isBordered = false
                    button.bezelStyle = .inline
                    button.setButtonType(.momentaryPushIn)
                    button.target = self
                    button.action = #selector(favoriteClicked(_:))
                    button.imagePosition = .imageOnly
                    (button.cell as? NSButtonCell)?.imageScaling = .scaleProportionallyDown
                }
                let imageName = song.isFavorite ? "star.fill" : "star"
                let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Favorite")!
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))!
                if song.isFavorite {
                    button.contentTintColor = .systemYellow
                } else {
                    button.contentTintColor = .tertiaryLabelColor
                }
                button.image = image
                button.tag = row
                return button
            }

            // Text-based columns
            let tf: NSTextField
            if let reused = tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField {
                tf = reused
            } else {
                tf = NSTextField(labelWithString: "")
                tf.identifier = id
                tf.lineBreakMode = .byTruncatingTail
            }

            switch id.rawValue {
            case "title":     tf.stringValue = song.title
            case "artist":    tf.stringValue = song.artist
            case "album":     tf.stringValue = song.album
            case "genre":     tf.stringValue = song.genre
            case "duration":  tf.stringValue = song.formattedDuration
            case "tempo":     tf.stringValue = "\(Int(song.tempo)) BPM"
            case "tracks":    tf.stringValue = "\(song.trackCount)"
            case "playCount": tf.stringValue = song.playCount > 0 ? "\(song.playCount)" : ""
            case "dateAdded": tf.stringValue = song.dateAdded.formatted(date: .abbreviated, time: .omitted)
            case "lastPlayed":
                tf.stringValue = song.lastPlayed?.formatted(date: .abbreviated, time: .shortened) ?? ""
            default: break
            }
            return tf
        }

        @objc func favoriteClicked(_ sender: NSButton) {
            let row = sender.tag
            guard row >= 0, row < songs.count else { return }
            parent.onToggleFavorite(songs[row])
            tableView?.reloadData(
                forRowIndexes: IndexSet(integer: row),
                columnIndexes: IndexSet(0..<(tableView?.numberOfColumns ?? 0))
            )
        }

        // MARK: Selection

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelection, let tableView else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            var ids = Set<UUID>()
            for row in tableView.selectedRowIndexes where row < songs.count {
                ids.insert(songs[row].id)
            }
            parent.selection = ids
        }

        func syncSelection() {
            guard let tableView, !isUpdatingSelection else { return }
            isUpdatingSelection = true
            defer { isUpdatingSelection = false }

            let target = IndexSet(
                songs.enumerated().compactMap { i, s in parent.selection.contains(s.id) ? i : nil }
            )
            if tableView.selectedRowIndexes != target {
                tableView.selectRowIndexes(target, byExtendingSelection: false)
            }
        }

        // MARK: Sorting

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
            guard !isUpdatingSortOrder else { return }
            let mapped: [KeyPathComparator<Song>] = tableView.sortDescriptors.compactMap { d in
                guard let key = d.key else { return nil }
                let order: SortOrder = d.ascending ? .forward : .reverse
                switch key {
                case "title":     return KeyPathComparator(\Song.title, order: order)
                case "artist":    return KeyPathComparator(\Song.artist, order: order)
                case "album":     return KeyPathComparator(\Song.album, order: order)
                case "genre":     return KeyPathComparator(\Song.genre, order: order)
                case "duration":  return KeyPathComparator(\Song.duration, order: order)
                case "tempo":     return KeyPathComparator(\Song.tempo, order: order)
                case "tracks":    return KeyPathComparator(\Song.trackCount, order: order)
                case "playCount": return KeyPathComparator(\Song.playCount, order: order)
                case "dateAdded": return KeyPathComparator(\Song.dateAdded, order: order)
                case "lastPlayed": return KeyPathComparator(\Song.lastPlayed, order: order)
                default: return nil
                }
            }
            if !mapped.isEmpty { parent.sortOrder = mapped }
        }

        func syncSortDescriptors() {
            guard let tableView else { return }
            isUpdatingSortOrder = true
            defer { isUpdatingSortOrder = false }

            let descs: [NSSortDescriptor] = parent.sortOrder.compactMap { comp in
                let asc = comp.order == .forward
                for (kp, key) in [(\Song.title, "title"), (\Song.artist, "artist"),
                                   (\Song.album, "album"), (\Song.genre, "genre")]
                    as [(KeyPath<Song, String>, String)]
                {
                    if comp == KeyPathComparator(kp, order: comp.order) {
                        return NSSortDescriptor(key: key, ascending: asc,
                                                selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
                    }
                }
                for (kp, key) in [(\Song.duration, "duration"), (\Song.tempo, "tempo")]
                    as [(KeyPath<Song, Double>, String)]
                {
                    if comp == KeyPathComparator(kp, order: comp.order) {
                        return NSSortDescriptor(key: key, ascending: asc)
                    }
                }
                for (kp, key) in [(\Song.trackCount, "tracks"), (\Song.playCount, "playCount")]
                    as [(KeyPath<Song, Int>, String)]
                {
                    if comp == KeyPathComparator(kp, order: comp.order) {
                        return NSSortDescriptor(key: key, ascending: asc)
                    }
                }
                if comp == KeyPathComparator(\Song.dateAdded, order: comp.order) {
                    return NSSortDescriptor(key: "dateAdded", ascending: asc)
                }
                if comp == KeyPathComparator(\Song.lastPlayed, order: comp.order) {
                    return NSSortDescriptor(key: "lastPlayed", ascending: asc)
                }
                return nil
            }
            if tableView.sortDescriptors != descs { tableView.sortDescriptors = descs }
        }

        // MARK: Double Click & Context Menu

        @objc func doubleClick(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < songs.count else { return }
            parent.onPlay(songs[row])
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < songs.count else { return }

            if !tableView.selectedRowIndexes.contains(row) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }

            let play = NSMenuItem(title: "Play", action: #selector(menuPlay), keyEquivalent: "")
            play.target = self
            menu.addItem(play)
            menu.addItem(.separator())

            // Favorite toggle
            let selectedSongs = tableView.selectedRowIndexes.compactMap { i in
                i < songs.count ? songs[i] : nil
            }
            let allFavorited = selectedSongs.allSatisfy(\.isFavorite)
            let favTitle = allFavorited ? "Unfavorite" : "Favorite"
            let fav = NSMenuItem(title: favTitle, action: #selector(menuToggleFavorite), keyEquivalent: "")
            fav.target = self
            menu.addItem(fav)

            menu.addItem(.separator())
            let showInFinder = NSMenuItem(title: "Show in Finder", action: #selector(menuShowInFinder), keyEquivalent: "")
            showInFinder.target = self
            menu.addItem(showInFinder)
            menu.addItem(.separator())
            let delete = NSMenuItem(title: "Delete", action: #selector(menuDelete), keyEquivalent: "")
            delete.target = self
            menu.addItem(delete)
        }

        @objc func menuPlay() {
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < songs.count else { return }
            parent.onPlay(songs[row])
        }

        @objc func menuToggleFavorite() {
            guard let tableView else { return }
            let rows = tableView.selectedRowIndexes
            for row in rows where row < songs.count {
                parent.onToggleFavorite(songs[row])
            }
            tableView.reloadData(
                forRowIndexes: rows,
                columnIndexes: IndexSet(0..<tableView.numberOfColumns)
            )
        }

        @objc func menuShowInFinder() {
            guard let tableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < songs.count else { return }
            parent.onShowInFinder(songs[row])
        }

        @objc func menuDelete() { parent.onDelete() }

        // MARK: Row Drag (to playlists)

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard row < songs.count else { return nil }
            return songs[row].id.uuidString as NSString
        }

        // MARK: File Drop

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                        proposedRow row: Int, proposedDropOperation: NSTableView.DropOperation) -> NSDragOperation {
            .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                        row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let urls = info.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            ) as? [URL], !urls.isEmpty else { return false }
            parent.onDrop(urls)
            return true
        }
    }
}

// MARK: - NSTableView subclass for delete-key handling

final class KeyHandlingTableView: NSTableView {
    weak var coordinator: NativeSongTableView.Coordinator?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // spacebar — play selected or toggle play/pause
            guard let coordinator else { return }
            let row = selectedRow
            let song = (row >= 0 && row < coordinator.songs.count) ? coordinator.songs[row] : nil
            coordinator.parent.onSpacebar(song)
        case 51, 117: // delete / forward-delete
            coordinator?.parent.onDelete()
        default:
            super.keyDown(with: event)
        }
    }
}
