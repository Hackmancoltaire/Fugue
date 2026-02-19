import SwiftUI

struct PianoKeyboardView: View {
    let noteRange: ClosedRange<UInt8>
    let activeNotes: [NoteEvent]
    var mutedChannels: Set<UInt8> = []

    private static let channelColors: [Color] = [
        .blue, .red, .green, .orange,
        .purple, .cyan, .pink, .yellow,
        .mint, .indigo, .teal, .brown,
        Color(red: 0.8, green: 0.2, blue: 0.4),
        Color(red: 0.2, green: 0.8, blue: 0.4),
        Color(red: 0.4, green: 0.2, blue: 0.8),
        Color(red: 0.8, green: 0.6, blue: 0.2),
    ]

    static func colorForChannel(_ channel: UInt8) -> Color {
        channelColors[Int(channel) % channelColors.count]
    }

    private static func isBlackKey(_ note: UInt8) -> Bool {
        let pc = note % 12
        return pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10
    }

    private var activeNoteSet: [UInt8: UInt8] {
        // Map note number -> channel (last wins for color), excluding muted channels
        var result: [UInt8: UInt8] = [:]
        for note in activeNotes where !mutedChannels.contains(note.channel) {
            result[note.noteNumber] = note.channel
        }
        return result
    }

    var body: some View {
        Canvas { context, size in
            let whiteKeys = (noteRange.lowerBound...noteRange.upperBound).filter { !Self.isBlackKey($0) }
            guard !whiteKeys.isEmpty else { return }

            let whiteKeyWidth = size.width / CGFloat(whiteKeys.count)
            let blackKeyWidth = whiteKeyWidth * 0.6
            let blackKeyHeight = size.height * 0.6
            let activeSet = activeNoteSet

            // Map each note in range to an x position
            var noteXPositions: [UInt8: CGFloat] = [:]
            var whiteIndex = 0
            for note in noteRange.lowerBound...noteRange.upperBound {
                if Self.isBlackKey(note) {
                    // Black key sits between previous and next white key
                    let x = CGFloat(whiteIndex) * whiteKeyWidth - blackKeyWidth / 2
                    noteXPositions[note] = x
                } else {
                    let x = CGFloat(whiteIndex) * whiteKeyWidth
                    noteXPositions[note] = x
                    whiteIndex += 1
                }
            }

            // Draw white keys
            for note in noteRange.lowerBound...noteRange.upperBound {
                guard !Self.isBlackKey(note), let x = noteXPositions[note] else { continue }
                let rect = CGRect(x: x, y: 0, width: whiteKeyWidth - 1, height: size.height)
                if let channel = activeSet[note] {
                    context.fill(Path(rect), with: .color(Self.colorForChannel(channel).opacity(0.8)))
                } else {
                    context.fill(Path(rect), with: .color(.white.opacity(0.9)))
                }
                context.stroke(Path(rect), with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
            }

            // Draw black keys on top
            for note in noteRange.lowerBound...noteRange.upperBound {
                guard Self.isBlackKey(note), let x = noteXPositions[note] else { continue }
                let rect = CGRect(x: x, y: 0, width: blackKeyWidth, height: blackKeyHeight)
                if let channel = activeSet[note] {
                    context.fill(Path(rect), with: .color(Self.colorForChannel(channel)))
                } else {
                    context.fill(Path(rect), with: .color(Color(white: 0.15)))
                }
                context.stroke(Path(rect), with: .color(.black.opacity(0.5)), lineWidth: 0.5)
            }
        }
        .frame(height: 60)
    }
}
