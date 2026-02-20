import SwiftUI
import SwiftData

@main
struct FugueApp: App {
    @State private var libraryManager = LibraryManager()
    @State private var playbackService = PlaybackService()
    @State private var midiOutputService = MIDIOutputService()

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

    /// Installs an app-wide local event monitor for spacebar so play/pause works
    /// from any window (visualizer, settings, etc.) that doesn't handle it itself.
    private func installSpacebarMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle unmodified spacebar
            guard event.keyCode == 49, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [] else {
                return event
            }
            // If the first responder is our KeyHandlingTableView, it handles spacebar itself
            if event.window?.firstResponder is KeyHandlingTableView {
                return event
            }
            // Toggle play/pause from any other context
            if playbackService.currentSong != nil {
                playbackService.togglePlayPause()
                return nil // consumed
            }
            return event
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(libraryManager)
                .environment(playbackService)
                .environment(midiOutputService)
                .onAppear {
                    playbackService.midiOutput = midiOutputService
                    midiOutputService.onEndpointChanged = { [weak playbackService] in
                        playbackService?.rerouteMIDIOutput()
                    }
                    installSpacebarMonitor()
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            FugueCommands(playbackService: playbackService)
        }

        Window("Note Visualization", id: "note-visualization") {
            NoteVisualizationView()
                .environment(playbackService)
                .environment(midiOutputService)
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 900, height: 400)

        Settings {
            SettingsView()
                .environment(midiOutputService)
                .environment(playbackService)
        }
    }
}

struct FugueCommands: Commands {
    let playbackService: PlaybackService
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

        CommandMenu("Playback") {
            Button(playbackService.state == .playing ? "Pause" : "Play") {
                playbackService.togglePlayPause()
            }
            .disabled(playbackService.currentSong == nil)

            Button("Stop") {
                playbackService.stop()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(playbackService.currentSong == nil)
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
