import SwiftUI

struct SettingsView: View {
    @AppStorage("importMode") private var importMode: ImportMode = .move
    @Environment(MIDIOutputService.self) private var midiOutput
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                Form {
                    Picker("When importing files:", selection: $importMode) {
                        ForEach(ImportMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(20)
                .frame(width: 350)
            }

            Tab("MIDI Output", systemImage: "cable.connector") {
                Form {
                    @Bindable var output = midiOutput
                    Picker("Destination:", selection: $output.selectedDestinationName) {
                        Text("Local Synthesis").tag(nil as String?)
                        ForEach(midiOutput.availableDestinations) { dest in
                            Text(dest.name).tag(Optional(dest.name))
                        }
                    }
                    .onChange(of: midiOutput.selectedDestinationName) {
                        playbackService.rerouteMIDIOutput()
                    }

                    if midiOutput.availableDestinations.isEmpty {
                        Text("No external MIDI destinations found.\nEnable the IAC Driver in Audio MIDI Setup or connect a MIDI device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(width: 350)
            }
        }
    }
}
