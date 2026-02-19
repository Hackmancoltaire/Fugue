import SwiftUI
import SwiftData

@main
struct FugueApp: App {
    @State private var libraryManager = LibraryManager()
    @State private var playbackService = PlaybackService()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Song.self,
            Playlist.self,
            PlaylistEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(libraryManager)
                .environment(playbackService)
        }
        .modelContainer(sharedModelContainer)
        .commands {
            FugueCommands()
        }

        Window("Note Visualization", id: "note-visualization") {
            NoteVisualizationView()
                .environment(playbackService)
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 900, height: 400)

        Settings {
            SettingsView()
        }
    }
}

struct FugueCommands: Commands {
    @FocusedValue(\.createPlaylist) private var createPlaylist
    @FocusedValue(\.openVisualization) private var openVisualization

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Playlist") {
                createPlaylist?()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(createPlaylist == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Note Visualization") {
                openVisualization?()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
            .disabled(openVisualization == nil)
        }
    }
}

private struct OpenVisualizationAction: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openVisualization: (() -> Void)? {
        get { self[OpenVisualizationAction.self] }
        set { self[OpenVisualizationAction.self] = newValue }
    }
}
