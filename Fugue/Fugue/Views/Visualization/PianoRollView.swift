import SwiftUI

struct PianoRollView: View {
    let noteSequence: NoteSequence?
    let currentPosition: TimeInterval
    let activeNotes: [NoteEvent]
    let noteRange: ClosedRange<UInt8>
    var mutedChannels: Set<UInt8> = []
    let visibleDuration: TimeInterval = 5.0

    private var activeNoteSet: Set<Int> {
        // Use a combined key of startTime hash + noteNumber for identity
        Set(activeNotes.map { Int($0.noteNumber) << 16 | Int($0.channel) })
    }

    private static func isBlackKey(_ note: UInt8) -> Bool {
        let pc = note % 12
        return pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10
    }

    var body: some View {
        Canvas { context, size in
            guard let noteSequence else { return }

            let totalNotes = Int(noteRange.upperBound) - Int(noteRange.lowerBound) + 1
            guard totalNotes > 0 else { return }

            // X axis: pitch mapping aligned with keyboard
            // Count white keys for positioning
            let whiteKeys = (noteRange.lowerBound...noteRange.upperBound).filter { !Self.isBlackKey($0) }
            guard !whiteKeys.isEmpty else { return }
            let whiteKeyWidth = size.width / CGFloat(whiteKeys.count)
            let blackKeyWidth = whiteKeyWidth * 0.6

            var noteXPositions: [UInt8: (x: CGFloat, width: CGFloat)] = [:]
            var whiteIndex = 0
            for note in noteRange.lowerBound...noteRange.upperBound {
                if Self.isBlackKey(note) {
                    let x = CGFloat(whiteIndex) * whiteKeyWidth - blackKeyWidth / 2
                    noteXPositions[note] = (x: x, width: blackKeyWidth)
                } else {
                    let x = CGFloat(whiteIndex) * whiteKeyWidth
                    noteXPositions[note] = (x: x, width: whiteKeyWidth - 1)
                    whiteIndex += 1
                }
            }

            // Y axis: time. Bottom = currentPosition (now), Top = currentPosition + visibleDuration (future)
            let windowStart = currentPosition
            let windowEnd = currentPosition + visibleDuration

            // Draw subtle grid lines for white keys
            for note in noteRange.lowerBound...noteRange.upperBound {
                guard !Self.isBlackKey(note), let pos = noteXPositions[note] else { continue }
                var path = Path()
                path.move(to: CGPoint(x: pos.x, y: 0))
                path.addLine(to: CGPoint(x: pos.x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }

            // Draw notes
            let visibleNotes = noteSequence.notesInRange(from: windowStart, to: windowEnd)

            for note in visibleNotes {
                guard let pos = noteXPositions[note.noteNumber] else { continue }

                // Map time to y: future (windowEnd) at top (y=0), now (windowStart) at bottom (y=height)
                let noteTopTime = min(note.endTime, windowEnd)
                let noteBottomTime = max(note.startTime, windowStart)

                let yTop = size.height * (1.0 - (noteTopTime - windowStart) / visibleDuration)
                let yBottom = size.height * (1.0 - (noteBottomTime - windowStart) / visibleDuration)

                let rect = CGRect(
                    x: pos.x + 1,
                    y: yTop,
                    width: pos.width - 2,
                    height: max(yBottom - yTop, 2)
                )

                let isMuted = mutedChannels.contains(note.channel)
                let isActive = note.startTime <= currentPosition && note.endTime > currentPosition
                let color = PianoKeyboardView.colorForChannel(note.channel)
                let opacity: Double = isMuted ? 0.1 : (isActive ? 1.0 : 0.6)
                let cornerRadius: CGFloat = 3

                let roundedRect = Path(roundedRect: rect, cornerRadius: cornerRadius)
                context.fill(roundedRect, with: .color(color.opacity(opacity)))

                if isActive {
                    context.stroke(roundedRect, with: .color(.white.opacity(0.4)), lineWidth: 1)
                }
            }

            // Draw playhead line at bottom
            var playhead = Path()
            playhead.move(to: CGPoint(x: 0, y: size.height))
            playhead.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(playhead, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }
        .background(.black)
    }
}
