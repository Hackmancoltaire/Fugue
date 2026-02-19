import SwiftUI

struct SettingsView: View {
    @AppStorage("importMode") private var importMode: ImportMode = .move

    var body: some View {
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
}
