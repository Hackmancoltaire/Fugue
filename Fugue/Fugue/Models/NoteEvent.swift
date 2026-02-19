import Foundation

struct NoteEvent: Sendable {
    let noteNumber: UInt8
    let channel: UInt8
    let velocity: UInt8
    let startTime: TimeInterval
    let endTime: TimeInterval
    let trackIndex: Int
}

struct NoteSequence: Sendable {
    let notes: [NoteEvent]  // sorted by startTime
    let minNote: UInt8
    let maxNote: UInt8
    let duration: TimeInterval
    let channelInstruments: [Int: String]

    /// Returns all notes sounding at the given time. O(log n + k).
    func activeNotes(at time: TimeInterval) -> [NoteEvent] {
        guard !notes.isEmpty else { return [] }

        // Binary search for rightmost note with startTime <= time
        var lo = 0
        var hi = notes.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime <= time {
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        // hi is now the index of the rightmost note with startTime <= time
        guard hi >= 0 else { return [] }

        var result: [NoteEvent] = []
        for i in stride(from: hi, through: 0, by: -1) {
            let note = notes[i]
            if note.endTime <= time { continue }
            if note.startTime > time { continue }
            result.append(note)
        }
        return result
    }

    /// Returns all notes that overlap the time window [from, to). Used by piano roll.
    func notesInRange(from start: TimeInterval, to end: TimeInterval) -> [NoteEvent] {
        guard !notes.isEmpty else { return [] }

        // Binary search for first note that could overlap: startTime < end
        // We need notes where startTime < end AND endTime > start
        var lo = 0
        var hi = notes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if notes[mid].startTime < end {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo is now the first note with startTime >= end, so all candidates are before lo

        var result: [NoteEvent] = []
        for i in 0..<lo {
            let note = notes[i]
            if note.endTime > start {
                result.append(note)
            }
        }
        return result
    }
}
