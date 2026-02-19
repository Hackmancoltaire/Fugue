import SwiftUI

struct NoteVisualizationView: View {
    @Environment(PlaybackService.self) private var playbackService

    private var noteRange: ClosedRange<UInt8> {
        guard let seq = playbackService.noteSequence else {
            return 60...72
        }
        let low = max(0, Int(seq.minNote) - 2)
        let high = min(127, Int(seq.maxNote) + 2)
        return UInt8(low)...UInt8(high)
    }

    private var mutedChannels: Set<UInt8> {
        Set(playbackService.currentSong?.mutedChannels.map { UInt8($0) } ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            PianoRollView(
                noteSequence: playbackService.noteSequence,
                currentPosition: playbackService.currentPosition,
                activeNotes: playbackService.activeNotes,
                noteRange: noteRange,
                mutedChannels: mutedChannels
            )

            Divider()

            PianoKeyboardView(
                noteRange: noteRange,
                activeNotes: playbackService.activeNotes,
                mutedChannels: mutedChannels
            )
        }
        .background(.black)
    }
}
