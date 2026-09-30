import Foundation
import Model

/// A made-up file for the Import screen's previews.
enum ImportPreviewData {
    /// A wide sheet in the Italian style that no saved profile fits: two
    /// accounts of the preview library, a quantity column with no account
    /// yet, a new deposit, a loan written as positive amounts, a cell that
    /// can't be read, and a note column.
    static let sheet = """
        Data;Conto Fineco;Directa;BTC (qtà);Nuovo deposito;Prestito auto;Note
        31/10/2026;5.310,20;41.200,00;0,4215;2.000,00;8.000,00;
        30/11/2026;5.120,00;41.950,50;0,4215;2.050,00;7.600,00;bonus
        31/12/2026;n/d;42.300,00;0,43;2.100,00;7.200,00;
        """

    static let fileName = "net-worth-2026.csv"

    /// An import of ``sheet`` against `library`, on `step` (Done needs the
    /// import run; see `ImportPreviewHost`).
    @MainActor
    static func controller(library: Library, step: ImportStep, guided: Bool = false) -> ImportController {
        let controller = ImportController(library: library, guided: guided)
        controller.open(Data(sheet.utf8), fileName: fileName)
        if guided, let profile = controller.flow.profileFits.first?.profile {
            controller.flow.useProfile(profile.id)
        }
        controller.flow.show(step)
        return controller
    }
}
