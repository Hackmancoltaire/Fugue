import AudioToolbox
import Foundation
import Observation

@Observable
class PlaybackService {
    enum State {
        case stopped
        case playing
        case paused
    }

    var state: State = .stopped
    var currentSong: Song?
    var currentPosition: TimeInterval = 0
    var duration: TimeInterval = 0
    var noteSequence: NoteSequence?
    var activeNotes: [NoteEvent] = []
    private(set) var isScrubbing = false

    private var musicPlayer: MusicPlayer?
    private var wasPlayingBeforeScrub = false
    private var musicSequence: MusicSequence?
    private var currentURL: URL?
    private var timer: Timer?
    private var sequenceLengthBeats: MusicTimeStamp = 0

    // MARK: - Playback Controls

    func play(_ song: Song, url: URL) {
        stop()

        var sequence: MusicSequence?
        guard NewMusicSequence(&sequence) == noErr, let sequence else { return }
        guard MusicSequenceFileLoad(sequence, url as CFURL, .midiType, []) == noErr else {
            DisposeMusicSequence(sequence)
            return
        }

        self.musicSequence = sequence
        self.currentURL = url
        self.currentSong = song

        // Calculate duration
        self.sequenceLengthBeats = Self.sequenceDurationInBeats(sequence)
        var seconds: Float64 = 0
        MusicSequenceGetSecondsForBeats(sequence, sequenceLengthBeats, &seconds)
        self.duration = seconds

        // Apply initial muting
        applyMuting(for: song)

        // Create and start player
        var player: MusicPlayer?
        guard NewMusicPlayer(&player) == noErr, let player else { return }
        MusicPlayerSetSequence(player, sequence)
        MusicPlayerPreroll(player)
        MusicPlayerStart(player)
        self.musicPlayer = player

        self.noteSequence = try? MIDINoteExtractor.extractNotes(from: url)

        state = .playing
        startTimer()
    }

    func togglePlayPause() {
        switch state {
        case .stopped:
            break
        case .playing:
            pause()
        case .paused:
            resume()
        }
    }

    func pause() {
        guard let player = musicPlayer else { return }
        MusicPlayerStop(player)
        state = .paused
        stopTimer()
    }

    func resume() {
        guard let player = musicPlayer, let sequence = musicSequence else { return }
        if currentPosition >= duration {
            currentPosition = 0
        }
        // Always sync player to currentPosition (may have been scrubbed while paused)
        var beats: MusicTimeStamp = 0
        MusicSequenceGetBeatsForSeconds(sequence, currentPosition, &beats)
        MusicPlayerSetTime(player, beats)
        MusicPlayerStart(player)
        sendActiveNoteOns()
        state = .playing
        startTimer()
    }

    func stop() {
        stopTimer()
        if let player = musicPlayer {
            MusicPlayerStop(player)
            DisposeMusicPlayer(player)
        }
        musicPlayer = nil
        if let sequence = musicSequence {
            DisposeMusicSequence(sequence)
        }
        musicSequence = nil
        currentURL = nil
        state = .stopped
        currentSong = nil
        currentPosition = 0
        duration = 0
        sequenceLengthBeats = 0
        noteSequence = nil
        activeNotes = []
    }

    func beginScrub() {
        guard musicPlayer != nil else { return }
        wasPlayingBeforeScrub = state == .playing
        isScrubbing = true
        if let player = musicPlayer {
            MusicPlayerStop(player)
        }
        sendAllNotesOff()
        stopTimer()
    }

    func scrub(to position: TimeInterval) {
        guard musicPlayer != nil else { return }
        // Visual only — don't touch the player until endScrub
        currentPosition = position
        activeNotes = noteSequence?.activeNotes(at: position) ?? []
    }

    func endScrub() {
        isScrubbing = false
        guard let player = musicPlayer, let sequence = musicSequence else { return }
        // Always move the player to the final scrub position
        var beats: MusicTimeStamp = 0
        MusicSequenceGetBeatsForSeconds(sequence, currentPosition, &beats)
        MusicPlayerSetTime(player, beats)
        if wasPlayingBeforeScrub {
            MusicPlayerStart(player)
            sendActiveNoteOns()
            state = .playing
            startTimer()
        }
    }

    func seek(to position: TimeInterval) {
        guard let player = musicPlayer, let sequence = musicSequence else { return }
        sendAllNotesOff()
        var beats: MusicTimeStamp = 0
        MusicSequenceGetBeatsForSeconds(sequence, position, &beats)
        MusicPlayerSetTime(player, beats)
        currentPosition = position
        activeNotes = noteSequence?.activeNotes(at: position) ?? []
        if state == .playing {
            sendActiveNoteOns()
        }
    }

    // MARK: - Muting

    func updateMutedChannels(for song: Song) {
        guard currentSong?.id == song.id else { return }
        applyMuting(for: song)
    }

    private func applyMuting(for song: Song) {
        guard let sequence = musicSequence else { return }

        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        let mutedSet = Set(song.mutedChannels)

        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let track else { continue }

            // Match sequence track to our TrackInfo by index
            let shouldMute: Bool
            if let info = song.trackInfos.first(where: { $0.index == Int(i) }),
               let channel = info.channel {
                shouldMute = mutedSet.contains(channel)
            } else {
                shouldMute = false
            }

            var muteStatus = DarwinBoolean(shouldMute)
            MusicTrackSetProperty(
                track,
                kSequenceTrackProperty_MuteStatus,
                &muteStatus,
                UInt32(MemoryLayout<DarwinBoolean>.size)
            )
        }
    }

    // MARK: - Note Chasing

    /// Sends CC#123 (All Notes Off) on every channel to silence the synth immediately.
    private func sendAllNotesOff() {
        guard let sequence = musicSequence else { return }
        var graph: AUGraph?
        MusicSequenceGetAUGraph(sequence, &graph)
        guard let graph else { return }

        var synthUnit: AudioUnit?
        var nodeCount: UInt32 = 0
        AUGraphGetNodeCount(graph, &nodeCount)
        for i in 0..<nodeCount {
            var node = AUNode()
            AUGraphGetIndNode(graph, i, &node)
            var desc = AudioComponentDescription()
            AUGraphNodeInfo(graph, node, &desc, nil)
            if desc.componentType == kAudioUnitType_MusicDevice {
                AUGraphNodeInfo(graph, node, nil, &synthUnit)
                break
            }
        }
        guard let unit = synthUnit else { return }

        for ch: UInt32 in 0..<16 {
            // CC#123 = All Notes Off
            MusicDeviceMIDIEvent(unit, 0xB0 | ch, 123, 0, 0)
        }
    }

    /// Re-triggers noteOn for all notes that should be sounding at the current position.
    /// Called on resume/seek so notes whose noteOn occurred before the playhead aren't silent.
    private func sendActiveNoteOns() {
        guard let sequence = musicSequence,
              let notes = noteSequence else { return }

        var graph: AUGraph?
        MusicSequenceGetAUGraph(sequence, &graph)
        guard let graph else { return }

        // Find the DLS synthesizer AudioUnit in the graph
        var synthUnit: AudioUnit?
        var nodeCount: UInt32 = 0
        AUGraphGetNodeCount(graph, &nodeCount)
        for i in 0..<nodeCount {
            var node = AUNode()
            AUGraphGetIndNode(graph, i, &node)
            var desc = AudioComponentDescription()
            AUGraphNodeInfo(graph, node, &desc, nil)
            if desc.componentType == kAudioUnitType_MusicDevice {
                AUGraphNodeInfo(graph, node, nil, &synthUnit)
                break
            }
        }
        guard let unit = synthUnit else { return }

        let mutedSet = Set(currentSong?.mutedChannels ?? [])
        let active = notes.activeNotes(at: currentPosition)

        for note in active {
            if mutedSet.contains(Int(note.channel)) { continue }
            MusicDeviceMIDIEvent(
                unit,
                0x90 | UInt32(note.channel),
                UInt32(note.noteNumber),
                UInt32(note.velocity),
                0
            )
        }
    }

    // MARK: - Private

    private func handlePlaybackComplete() {
        guard let player = musicPlayer else { return }
        MusicPlayerStop(player)
        currentSong?.playCount += 1
        state = .paused
        currentPosition = duration
        activeNotes = []
        stopTimer()
    }

    private static func sequenceDurationInBeats(_ sequence: MusicSequence) -> MusicTimeStamp {
        var trackCount: UInt32 = 0
        MusicSequenceGetTrackCount(sequence, &trackCount)

        var maxLength: MusicTimeStamp = 0
        for i in 0..<trackCount {
            var track: MusicTrack?
            MusicSequenceGetIndTrack(sequence, i, &track)
            guard let track else { continue }
            var length: MusicTimeStamp = 0
            var size = UInt32(MemoryLayout<MusicTimeStamp>.size)
            MusicTrackGetProperty(track, kSequenceTrackProperty_TrackLength, &length, &size)
            maxLength = max(maxLength, length)
        }
        return maxLength
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self,
                      let player = self.musicPlayer,
                      let sequence = self.musicSequence else { return }

                var beats: MusicTimeStamp = 0
                MusicPlayerGetTime(player, &beats)

                if beats >= self.sequenceLengthBeats {
                    self.handlePlaybackComplete()
                    return
                }

                var seconds: Float64 = 0
                MusicSequenceGetSecondsForBeats(sequence, beats, &seconds)
                self.currentPosition = seconds
                self.activeNotes = self.noteSequence?.activeNotes(at: seconds) ?? []
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
