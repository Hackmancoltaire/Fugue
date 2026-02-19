import Foundation
import MIDIKitSMF

enum MIDINoteExtractor {
    static func extractNotes(from url: URL) throws -> NoteSequence {
        let midiFile = try MIDIFile(midiFile: url)

        let ppq: UInt32
        switch midiFile.timeBase {
        case .musical(let ticksPerQuarterNote):
            ppq = UInt32(ticksPerQuarterNote)
        case .timecode:
            ppq = 480
        }

        // Build tempo map from all tracks: sorted array of (tick, bpm)
        var tempoChanges: [(tick: UInt32, bpm: Double)] = []

        for track in midiFile.tracks {
            var trackTicks: UInt32 = 0
            for event in track.events {
                trackTicks += deltaTicks(event)
                if case .tempo(_, let e) = event {
                    tempoChanges.append((tick: trackTicks, bpm: e.bpm))
                }
            }
        }

        tempoChanges.sort { $0.tick < $1.tick }

        // Default tempo if none specified
        if tempoChanges.isEmpty || tempoChanges[0].tick > 0 {
            tempoChanges.insert((tick: 0, bpm: 120.0), at: 0)
        }

        // Extract note events from all tracks
        struct PendingNote {
            let noteNumber: UInt8
            let channel: UInt8
            let velocity: UInt8
            let startTick: UInt32
            let trackIndex: Int
        }

        var notes: [NoteEvent] = []
        var channelInstrumentMap: [Int: String] = [:]

        for (trackIndex, track) in midiFile.tracks.enumerated() {
            var trackTicks: UInt32 = 0
            // Key: (channel, noteNumber)
            var pending: [UInt16: PendingNote] = [:]

            for event in track.events {
                trackTicks += deltaTicks(event)

                switch event {
                case .noteOn(_, let e):
                    let noteNum = e.note.number.uInt8Value
                    let channel = e.channel.uInt8Value
                    let velocity = e.velocity.midi1Value.uInt8Value
                    let key = UInt16(channel) << 8 | UInt16(noteNum)

                    if velocity == 0 {
                        // NoteOn with velocity 0 is a NoteOff
                        if let p = pending.removeValue(forKey: key) {
                            notes.append(NoteEvent(
                                noteNumber: p.noteNumber,
                                channel: p.channel,
                                velocity: p.velocity,
                                startTime: ticksToSeconds(p.startTick, ppq: ppq, tempoMap: tempoChanges),
                                endTime: ticksToSeconds(trackTicks, ppq: ppq, tempoMap: tempoChanges),
                                trackIndex: p.trackIndex
                            ))
                        }
                    } else {
                        // Close any existing note on same key (re-trigger)
                        if let p = pending.removeValue(forKey: key) {
                            notes.append(NoteEvent(
                                noteNumber: p.noteNumber,
                                channel: p.channel,
                                velocity: p.velocity,
                                startTime: ticksToSeconds(p.startTick, ppq: ppq, tempoMap: tempoChanges),
                                endTime: ticksToSeconds(trackTicks, ppq: ppq, tempoMap: tempoChanges),
                                trackIndex: p.trackIndex
                            ))
                        }
                        pending[key] = PendingNote(
                            noteNumber: noteNum,
                            channel: channel,
                            velocity: velocity,
                            startTick: trackTicks,
                            trackIndex: trackIndex
                        )
                    }

                case .noteOff(_, let e):
                    let noteNum = e.note.number.uInt8Value
                    let channel = e.channel.uInt8Value
                    let key = UInt16(channel) << 8 | UInt16(noteNum)

                    if let p = pending.removeValue(forKey: key) {
                        notes.append(NoteEvent(
                            noteNumber: p.noteNumber,
                            channel: p.channel,
                            velocity: p.velocity,
                            startTime: ticksToSeconds(p.startTick, ppq: ppq, tempoMap: tempoChanges),
                            endTime: ticksToSeconds(trackTicks, ppq: ppq, tempoMap: tempoChanges),
                            trackIndex: p.trackIndex
                        ))
                    }

                case .programChange(_, let e):
                    let channel = Int(e.channel.uInt8Value)
                    channelInstrumentMap[channel] = GeneralMIDI.instrumentName(for: Int(e.program))

                default:
                    break
                }
            }

            // Close any unclosed notes at end of track
            for p in pending.values {
                notes.append(NoteEvent(
                    noteNumber: p.noteNumber,
                    channel: p.channel,
                    velocity: p.velocity,
                    startTime: ticksToSeconds(p.startTick, ppq: ppq, tempoMap: tempoChanges),
                    endTime: ticksToSeconds(trackTicks, ppq: ppq, tempoMap: tempoChanges),
                    trackIndex: p.trackIndex
                ))
            }
        }

        notes.sort { $0.startTime < $1.startTime }

        // Fill in defaults for channels with notes but no program change
        let activeChannels = Set(notes.map { Int($0.channel) })
        for channel in activeChannels where channelInstrumentMap[channel] == nil {
            channelInstrumentMap[channel] = channel == 9
                ? "Percussion"
                : GeneralMIDI.instrumentName(for: 0)
        }

        let minNote = notes.map(\.noteNumber).min() ?? 0
        let maxNote = notes.map(\.noteNumber).max() ?? 127
        let duration = notes.map(\.endTime).max() ?? 0

        return NoteSequence(
            notes: notes,
            minNote: minNote,
            maxNote: maxNote,
            duration: duration,
            channelInstruments: channelInstrumentMap
        )
    }

    private static func ticksToSeconds(
        _ ticks: UInt32,
        ppq: UInt32,
        tempoMap: [(tick: UInt32, bpm: Double)]
    ) -> TimeInterval {
        var seconds: TimeInterval = 0
        var prevTick: UInt32 = 0
        var currentBPM: Double = 120.0

        for change in tempoMap {
            if change.tick >= ticks {
                break
            }
            let segmentTicks = change.tick - prevTick
            seconds += Double(segmentTicks) / Double(ppq) * (60.0 / currentBPM)
            prevTick = change.tick
            currentBPM = change.bpm
        }

        // Remaining ticks from last tempo change to target
        let remainingTicks = ticks - prevTick
        seconds += Double(remainingTicks) / Double(ppq) * (60.0 / currentBPM)

        return seconds
    }

    private static func deltaTicks(_ event: MIDIFileEvent) -> UInt32 {
        switch event.delta {
        case .ticks(let value):
            return value
        default:
            return 0
        }
    }
}
