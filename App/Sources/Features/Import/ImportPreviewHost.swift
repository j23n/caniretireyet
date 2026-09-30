import Foundation
import Model
import SwiftUI

/// The Import screen on a step, with a made-up file already read, for
/// previews. Use it inside `.previewEnvironment()`; for Done, the import
/// runs against the in-memory preview library.
struct ImportPreviewHost: View {
    let step: ImportStep
    var guided = false

    @Environment(LibraryStore.self) private var library
    @State private var model: ImportController?

    var body: some View {
        Group {
            if let model {
                ImportStepContent(model: model, isCompact: guided, chooseFile: {}, openFile: { _ in })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.page)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        ImportStepBar(model: model)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        ImportBottomBar(model: model)
                    }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Import")
        .task {
            let controller = ImportPreviewData.controller(library: library.library,
                                                          step: step == .done ? .preview : step, guided: guided)
            if step == .done {
                await controller.runImport(in: library)
            }
            model = controller
        }
    }
}
