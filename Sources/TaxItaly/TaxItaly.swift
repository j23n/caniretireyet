/// # TaxItaly
///
/// The Italian tax system (`it`), described in docs/tax/IT.md: regimes
/// (employee, professional, forfettario, impatriati), INPS, wrappers
/// (ordinary, pension fund, TFR) and yearly parameter files.
///
/// Parameter files live in `Resources/it/<year>.json`, one per tax year, and
/// every value cites its source. Implements `TaxKit.TaxSystem`.
///
/// `Resources` is processed (`.process`), which flattens folders: the files
/// end up at the bundle root, so load them with
/// `JSONParameterStore(system: "it", directory: Bundle.module.resourceURL!)`
/// (it reads only `<year>.json`), or switch the package to
/// `.copy("Resources/it")` to keep the folder.
///
/// Placeholder: this module is owned by another engineer.
enum TaxItalyModule {}
