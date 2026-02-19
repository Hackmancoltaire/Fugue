import SwiftUI

struct TransportBar: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.openWindow) private var openWindow
    @AppStorage("isVisualizationShown") private var isVisualizationShown = false

    var body: some View {
        if let song = playbackService.currentSong {
            HStack(spacing: 16) {
                // Song info
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: 200, alignment: .leading)

                // Controls
                HStack(spacing: 12) {
                    Button {
                        playbackService.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                    }

                    Button {
                        playbackService.togglePlayPause()
                    } label: {
                        Image(systemName: playbackService.state == .playing
                              ? "pause.fill" : "play.fill")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                }
                .buttonStyle(.plain)
                .font(.title2)

                // Progress slider
                Slider(
                    value: Binding(
                        get: { playbackService.currentPosition },
                        set: { playbackService.scrub(to: $0) }
                    ),
                    in: 0...max(playbackService.duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            playbackService.beginScrub()
                        } else {
                            playbackService.endScrub()
                        }
                    }
                )

                // Time display
                Text("\(formatTime(playbackService.currentPosition)) / \(formatTime(playbackService.duration))")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 100)

                // Visualization toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisualizationShown.toggle()
                    }
                } label: {
                    Image(systemName: isVisualizationShown ? "pianokeys.inverse" : "pianokeys")
                }
                .buttonStyle(.plain)
                .help("Toggle Note Visualization")

                // Open in window
                Button {
                    openWindow(id: "note-visualization")
                } label: {
                    Image(systemName: "macwindow.badge.plus")
                }
                .buttonStyle(.plain)
                .help("Open Visualization in Window")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
