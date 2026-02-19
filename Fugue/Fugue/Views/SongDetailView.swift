import SwiftUI

struct SongDetailView: View {
    @Bindable var song: Song
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PlaybackService.self) private var playbackService
    @FocusState private var focusedField: DetailField?

    private enum DetailField: Hashable {
        case title, artist, album, genre
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Editable header
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Title", text: $song.title, axis: .vertical)
                        .font(.title)
                        .fontWeight(.bold)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)

                    TextField("Artist", text: $song.artist)
                        .font(.title2)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .artist)

                    TextField("Album", text: $song.album)
                        .font(.title3)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .album)
                }

                Divider()

                // Metadata grid
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Genre")
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        TextField("Genre", text: $song.genre)
                            .textFieldStyle(.plain)
                            .focused($focusedField, equals: .genre)
                            .gridColumnAlignment(.leading)
                    }
                    MetadataRow(label: "Duration", value: song.formattedDuration)
                    MetadataRow(label: "Tempo", value: "\(Int(song.tempo)) BPM")
                    MetadataRow(
                        label: "Time Signature",
                        value: "\(song.timeSignatureNumerator)/\(song.timeSignatureDenominator)"
                    )
                    MetadataRow(label: "Tracks", value: "\(song.trackCount)")
                    MetadataRow(label: "Format", value: "Type \(song.fileFormat)")
                    MetadataRow(label: "PPQN", value: "\(song.ticksPerQuarterNote)")
                    MetadataRow(
                        label: "File Size",
                        value: ByteCountFormatter.string(
                            fromByteCount: song.fileSize,
                            countStyle: .file
                        )
                    )
                    MetadataRow(
                        label: "Date Added",
                        value: song.dateAdded.formatted(date: .abbreviated, time: .shortened)
                    )
                    MetadataRow(
                        label: "Date Modified",
                        value: song.dateModified.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                // Tracks
                if !song.trackInfos.isEmpty {
                    let instrumentTracks = song.trackInfos.filter(\.hasNotes)
                    let systemTracks = song.trackInfos.filter { !$0.hasNotes }

                    if !instrumentTracks.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instruments")
                                .font(.headline)

                            ForEach(instrumentTracks, id: \.self) { track in
                                HStack(spacing: 8) {
                                    Text("\(track.index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, alignment: .trailing)

                                    if let ch = track.channel {
                                        Circle()
                                            .fill(PianoKeyboardView.colorForChannel(UInt8(ch)))
                                            .frame(width: 12, height: 12)
                                    }

                                    Text(track.name)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    if let ch = track.channel {
                                        Button {
                                            toggleMute(channel: ch)
                                        } label: {
                                            Image(systemName: song.mutedChannels.contains(ch)
                                                  ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                                .foregroundStyle(song.mutedChannels.contains(ch)
                                                                 ? .secondary : .primary)
                                                .frame(width: 20)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    if !systemTracks.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("System Channels")
                                .font(.headline)

                            ForEach(systemTracks, id: \.self) { track in
                                HStack(spacing: 8) {
                                    Text("\(track.index + 1)")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 20, alignment: .trailing)

                                    if let ch = track.channel {
                                        Circle()
                                            .fill(PianoKeyboardView.colorForChannel(UInt8(ch)))
                                            .frame(width: 12, height: 12)
                                    }

                                    Text(track.name)
                                        .foregroundStyle(.secondary)

                                    if let ch = track.channel {
                                        Text("Ch \(ch + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()
                                }
                            }
                        }
                    }
                } else if !song.instruments.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Instruments")
                            .font(.headline)

                        ForEach(song.instruments, id: \.self) { instrument in
                            Text(instrument)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 250)
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue != nil {
                song.dateModified = Date()
            }
            if oldValue == .artist || oldValue == .album {
                libraryManager.reorganizeSong(song)
            }
        }
        .onDisappear {
            libraryManager.reorganizeSong(song)
        }
        .onAppear {
            backfillTrackInfosIfNeeded()
        }
        .onChange(of: song.id) {
            backfillTrackInfosIfNeeded()
        }
    }

    private func backfillTrackInfosIfNeeded() {
        guard let url = libraryManager.resolveURL(for: song),
              let metadata = try? MIDIMetadataExtractor.extract(from: url) else { return }
        if song.trackInfos != metadata.trackInfos {
            song.trackInfos = metadata.trackInfos
        }
        let freshChannels = metadata.channelInstruments
            .sorted { $0.key < $1.key }
            .map { ChannelInstrument(channel: $0.key, name: $0.value) }
        if song.channelInstruments != freshChannels {
            song.channelInstruments = freshChannels
        }
    }

    private func toggleMute(channel: Int) {
        if let index = song.mutedChannels.firstIndex(of: channel) {
            song.mutedChannels.remove(at: index)
        } else {
            song.mutedChannels.append(channel)
        }
        playbackService.updateMutedChannels(for: song)
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .gridColumnAlignment(.leading)
        }
    }
}
