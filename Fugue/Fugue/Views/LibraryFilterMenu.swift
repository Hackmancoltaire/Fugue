import SwiftUI

enum LibraryFilter: String, CaseIterable {
    case all
    case favorites
}

struct LibraryFilterMenu: View {
    @Binding var filter: LibraryFilter
    @Binding var sortOrder: [KeyPathComparator<Song>]
    @Binding var visibleColumns: VisibleColumnSet

    private var isFiltered: Bool { filter != .all }

    var body: some View {
        Menu {
            filterSection
            Divider()
            sortSection
            Divider()
            columnsSection
        } label: {
            Image(systemName: isFiltered
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .help("Filter & View Options")
    }

    // MARK: - Filter

    @ViewBuilder
    private var filterSection: some View {
        Picker(selection: $filter) {
            Text("All Songs").tag(LibraryFilter.all)
            Text("Favorites Only").tag(LibraryFilter.favorites)
        } label: {
            Text("Filter")
        }
        .pickerStyle(.inline)
    }

    // MARK: - Sort By

    @ViewBuilder
    private var sortSection: some View {
        Section("Sort By") {
            ForEach(SongColumn.allCases.filter(\.isSortable)) { col in
                Button {
                    handleSortTap(col)
                } label: {
                    HStack {
                        Text(col.displayTitle)
                        if isActiveSortColumn(col) {
                            Image(systemName: activeSortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var columnsSection: some View {
        Section("Columns") {
            ForEach(SongColumn.allCases.filter { $0 != .favorite }) { col in
                let isAlways = SongColumn.alwaysVisible.contains(col.rawValue)
                Toggle(col.displayTitle, isOn: Binding(
                    get: { visibleColumns.columns.contains(col.rawValue) },
                    set: { newValue in
                        var cols = visibleColumns.columns
                        if newValue {
                            cols.insert(col.rawValue)
                        } else {
                            cols.remove(col.rawValue)
                        }
                        visibleColumns = VisibleColumnSet(columns: cols)
                    }
                ))
                .disabled(isAlways)
            }
        }
    }

    // MARK: - Sort Helpers

    private var activeSortKeyPath: String? {
        guard let first = sortOrder.first else { return nil }
        for col in SongColumn.allCases {
            if first == comparator(for: col, order: first.order) {
                return col.rawValue
            }
        }
        return nil
    }

    private var activeSortAscending: Bool {
        sortOrder.first?.order == .forward
    }

    private func isActiveSortColumn(_ col: SongColumn) -> Bool {
        activeSortKeyPath == col.rawValue
    }

    private func handleSortTap(_ col: SongColumn) {
        if isActiveSortColumn(col) {
            let newOrder: SortOrder = activeSortAscending ? .reverse : .forward
            sortOrder = [comparator(for: col, order: newOrder)]
        } else {
            sortOrder = [comparator(for: col, order: .forward)]
        }
    }

    private func comparator(for col: SongColumn, order: SortOrder) -> KeyPathComparator<Song> {
        switch col {
        case .title:      return KeyPathComparator(\Song.title, order: order)
        case .artist:     return KeyPathComparator(\Song.artist, order: order)
        case .album:      return KeyPathComparator(\Song.album, order: order)
        case .genre:      return KeyPathComparator(\Song.genre, order: order)
        case .duration:   return KeyPathComparator(\Song.duration, order: order)
        case .tempo:      return KeyPathComparator(\Song.tempo, order: order)
        case .tracks:     return KeyPathComparator(\Song.trackCount, order: order)
        case .playCount:  return KeyPathComparator(\Song.playCount, order: order)
        case .dateAdded:  return KeyPathComparator(\Song.dateAdded, order: order)
        case .lastPlayed: return KeyPathComparator(\Song.lastPlayed, order: order)
        case .favorite:   return KeyPathComparator(\Song.title, order: order) // shouldn't happen
        }
    }
}
