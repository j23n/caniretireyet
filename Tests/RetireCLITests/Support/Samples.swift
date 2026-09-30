import Foundation

/// The made-up sample files in `Samples/`:
///
/// | File | What it covers |
/// | --- | --- |
/// | `sheet.csv` | Italian formats; values the example library has, one that differs, a mortgage written as positive amounts, a new account whose values stop early, a notes column |
/// | `ambiguous.csv` | dates that read as `dd/MM/yyyy` or `MM/dd/yyyy` |
/// | `broken.csv` | a date that doesn't exist and an amount that isn't a number |
enum Samples {
    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: "Samples/\(name)", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
