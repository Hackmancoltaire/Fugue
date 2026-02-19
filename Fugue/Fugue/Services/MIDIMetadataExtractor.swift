import Foundation
import MIDIKitSMF

struct MIDIMetadata {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var genre: String = ""
    var duration: TimeInterval = 0
    var tempo: Double = 120
    var timeSignatureNumerator: Int = 4
    var timeSignatureDenominator: Int = 4
    var trackCount: Int = 0
    var fileFormat: Int = 0
    var ticksPerQuarterNote: Int = 480
    var instruments: [String] = []
    var channelInstruments: [Int: String] = [:]
    var trackInfos: [TrackInfo] = []
    var fileSize: Int64 = 0
}

enum MIDIMetadataExtractor {
    static func extract(from url: URL) throws -> MIDIMetadata {
        let midiFile = try MIDIFile(midiFile: url)
        var metadata = MIDIMetadata()

        // File size
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        metadata.fileSize = (attributes[.size] as? Int64) ?? 0

        // Format
        metadata.fileFormat = Int(midiFile.format.rawValue)

        // Track count
        metadata.trackCount = midiFile.tracks.count

        // Time base
        switch midiFile.timeBase {
        case .musical(let ppq):
            metadata.ticksPerQuarterNote = Int(ppq)
        case .timecode:
            break
        }

        var tempo: Double = 120
        var foundTempo = false
        var firstTrackName: String?
        var instrumentNames: Set<String> = []
        var programNumbers: Set<Int> = []
        var channelInstrumentMap: [Int: String] = [:]
        var activeChannels: Set<Int> = []
        var maxTicks: UInt32 = 0
        var trackInfos: [TrackInfo] = []

        for (trackIndex, track) in midiFile.tracks.enumerated() {
            var trackTicks: UInt32 = 0
            var trackName: String?
            var trackChannelEvents: [Int: Int] = [:]  // channel → total event count
            var trackNoteChannels: [Int: Int] = [:]   // channel → noteOn count
            var trackHasNotes = false
            var trackProgram: [Int: Int] = [:]  // channel → program number

            for event in track.events {
                trackTicks += deltaTicks(event)

                switch event {
                case .tempo(_, let e):
                    if !foundTempo {
                        tempo = e.bpm
                        foundTempo = true
                    }

                case .timeSignature(_, let e):
                    metadata.timeSignatureNumerator = Int(e.numerator)
                    metadata.timeSignatureDenominator = Int(pow(2.0, Double(e.denominator)))

                case .text(_, let e):
                    switch e.textType {
                    case .trackOrSequenceName:
                        if !e.text.isEmpty {
                            trackName = e.text
                            if firstTrackName == nil { firstTrackName = e.text }
                        }
                    case .instrumentName:
                        if !e.text.isEmpty {
                            instrumentNames.insert(e.text)
                            if trackName == nil { trackName = e.text }
                        }
                    default:
                        break
                    }

                case .noteOn(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    if e.velocity.midi1Value.uInt8Value > 0 {
                        trackHasNotes = true
                        trackNoteChannels[ch, default: 0] += 1
                        activeChannels.insert(ch)
                    }
                    trackChannelEvents[ch, default: 0] += 1

                case .noteOff(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    trackChannelEvents[ch, default: 0] += 1

                case .programChange(_, let e):
                    let program = Int(e.program)
                    let ch = Int(e.channel.uInt8Value)
                    programNumbers.insert(program)
                    trackProgram[ch] = program
                    channelInstrumentMap[ch] = GeneralMIDI.instrumentName(for: program)
                    trackChannelEvents[ch, default: 0] += 1

                case .cc(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    trackChannelEvents[ch, default: 0] += 1

                case .pitchBend(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    trackChannelEvents[ch, default: 0] += 1

                case .pressure(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    trackChannelEvents[ch, default: 0] += 1

                case .notePressure(_, let e):
                    let ch = Int(e.channel.uInt8Value)
                    trackChannelEvents[ch, default: 0] += 1

                default:
                    break
                }
            }

            maxTicks = max(maxTicks, trackTicks)

            // Primary channel: prefer the note channel with most events, else any channel with most events
            let primaryChannel: Int?
            if let top = trackNoteChannels.max(by: { $0.value < $1.value }) {
                primaryChannel = top.key
            } else if let top = trackChannelEvents.max(by: { $0.value < $1.value }) {
                primaryChannel = top.key
            } else {
                primaryChannel = nil
            }

            // Build display name for this track
            let displayName: String
            if let trackName {
                displayName = trackName
            } else if let ch = primaryChannel {
                if let prog = trackProgram[ch] {
                    displayName = GeneralMIDI.instrumentName(for: prog)
                } else if ch == 9 {
                    displayName = "Percussion"
                } else if trackHasNotes {
                    displayName = GeneralMIDI.instrumentName(for: 0)
                } else {
                    displayName = "Channel \(ch + 1)"
                }
            } else {
                displayName = "Track \(trackIndex + 1)"
            }

            trackInfos.append(TrackInfo(
                index: trackIndex,
                name: displayName,
                channel: primaryChannel,
                hasNotes: trackHasNotes
            ))
        }

        metadata.tempo = tempo

        // Duration: (total_ticks / ppq) * (60 / bpm)
        if metadata.ticksPerQuarterNote > 0, tempo > 0 {
            let beats = Double(maxTicks) / Double(metadata.ticksPerQuarterNote)
            metadata.duration = beats * (60.0 / tempo)
        }

        // Combine text instrument names and GM program change names
        for program in programNumbers {
            instrumentNames.insert(GeneralMIDI.instrumentName(for: program))
        }
        metadata.instruments = instrumentNames.sorted()

        // Fill in defaults for channels with notes but no program change
        for channel in activeChannels where channelInstrumentMap[channel] == nil {
            channelInstrumentMap[channel] = channel == 9
                ? "Percussion"
                : GeneralMIDI.instrumentName(for: 0)
        }
        metadata.channelInstruments = channelInstrumentMap
        metadata.trackInfos = trackInfos

        // Title from first track name
        if let firstTrackName {
            metadata.title = firstTrackName
        }

        return metadata
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
