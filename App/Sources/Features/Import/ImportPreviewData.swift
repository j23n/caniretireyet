import Foundation
import Model

/// Made-up files for the Import screen's previews.
enum ImportPreviewData {
    /// Which made-up file a preview reads.
    enum File {
        /// ``sheet``: a net-worth spreadsheet.
        case sheet
        /// ``trades``: a broker's transactions.
        case trades
    }

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

    /// A broker's movements in the Italian style, for the trades layout: a
    /// deposit, buys, a dividend and its tax, a sale with a negative
    /// quantity, stamp duty, and a word the importer doesn't know.
    static let trades = """
        Data operazione;Tipo operazione;Ticker;Titolo;Quantità;Prezzo;Importo;Commissioni
        02/10/2026;Bonifico in entrata;;;;;3.000,00;
        05/10/2026;Acquisto;VWCE;Vanguard FTSE All-World;10;136,20;-1.367,00;5,00
        20/10/2026;Dividendo;VHYL;Vanguard FTSE All-World High Div;;;18,40;
        20/10/2026;Ritenuta su dividendo;VHYL;Vanguard FTSE All-World High Div;;;-4,78;
        12/11/2026;Vendita;VWCE;Vanguard FTSE All-World;-2;139,10;273,20;5,00
        31/12/2026;Imposta di bollo;;;;;-8,10;
        31/12/2026;Giroconto;;;;;250,00;
        """

    static let tradesFileName = "movimenti-2026.csv"

    /// An import of ``sheet`` (or ``trades``, into the preview library's
    /// first account) against `library`, on `step` (Done needs the import
    /// run; see `ImportPreviewHost`).
    @MainActor
    static func controller(library: Library, step: ImportStep, guided: Bool = false,
                           file: File = .sheet) -> ImportController {
        let controller = ImportController(library: library, guided: guided)
        switch file {
        case .sheet:
            controller.open(Data(sheet.utf8), fileName: fileName)
        case .trades:
            controller.open(Data(trades.utf8), fileName: tradesFileName)
            let account = library.sortedAccounts.first { $0.recordsTrades } ?? library.sortedAccounts.first
            controller.flow.setConstants { $0.account = account?.id }
        }
        if guided, let profile = controller.flow.profileFits.first?.profile {
            controller.flow.useProfile(profile.id)
        }
        controller.flow.show(step)
        return controller
    }
}
