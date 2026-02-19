import SwiftUI
import UniformTypeIdentifiers

struct ImportButton: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext
    @State private var isImporting = false

    var body: some View {
        Button {
            isImporting = true
        } label: {
            Label("Import", systemImage: "plus")
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.midi],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls {
                    guard url.startAccessingSecurityScopedResource() else { continue }
                    defer { url.stopAccessingSecurityScopedResource() }
                    do {
                        try libraryManager.importMIDIFile(from: url, context: modelContext)
                    } catch {
                        print("Import error: \(error)")
                    }
                }
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }
}
