import SwiftUI

extension View {
    /// A sheet's title, inline on iPhone and iPad, and its *Done* button,
    /// which runs `done` (usually dismissing the sheet).
    func sheetTitle(_ title: LocalizedStringKey, done: @escaping () -> Void) -> some View {
        navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
    }
}
