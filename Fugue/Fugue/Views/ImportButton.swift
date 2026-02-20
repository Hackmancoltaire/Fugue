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
        .disabled(libraryManager.isImporting)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.midi, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                libraryManager.importURLs(urls, context: modelContext)
            case .failure(let error):
                print("File selection error: \(error)")
            }
        }
    }
}
