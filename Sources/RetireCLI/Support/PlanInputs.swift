import Foundation
import Model
import Prices
import Storage
import TaxKit

/// What the plan, settings and instruments commands read from the tax
/// registry and the library, in the CLI's words: a scheme's ways to claim,
/// the fund type the planner works out, names for kinds. Everything comes
/// from the registry (``TaxSystems/registry()``), so a system registered
/// later brings its schemes, routes and wrappers with no change here.
enum PlanInputs {
    // MARK: Claim routes

    /// One way to claim a pension, as its scheme lists it.
    struct Route: Equatable {
        var id: String
        var label: String
        /// The ages it's offered at with the pension's details as they are.
        var ages: [Int]
        var paysLumpSum: Bool
    }

    /// The pension's options as the planner passes them to its scheme: a
    /// `fixed` pension's `fromAge` and `perYear` are its own keys.
    static func options(of pension: PlanPension) -> OptionValues {
        var options = OptionValues(pension.options.mapValues(optionValue))
        if pension.scheme == .fixed {
            if let age = pension.fromAge { options["fromAge"] = .number(Double(age)) }
            if let amount = pension.perYear {
                options["perYear"] = .number(NSDecimalNumber(decimal: amount).doubleValue)
            }
        }
        return options
    }

    /// The routes the pension's scheme offers with its details as they
    /// are: its claim options for a record started from the pension's
    /// options, asked as if still working and as if work had just stopped,
    /// from `today`'s year. Routes that need more contributions than the
    /// details say yet don't show. Empty when the scheme lists none.
    static func claimRoutes(for pension: PlanPension, birthDate: CalendarDate?, today: CalendarDate,
                            registry: TaxRegistry) -> [Route] {
        guard let owner = registry.systems.first(where: { $0.pensionScheme(pension.scheme.rawValue) != nil }),
              let scheme = owner.pensionScheme(pension.scheme.rawValue) else { return [] }
        let options = options(of: pension)
        let birth = birthDate ?? CalendarDate(year: today.year - 40, month: 1, day: 1) ?? today
        let record = scheme.startingRecord(options: options, year: today.year, parameters: owner.parameters)
        var routes: [Route] = []
        for stopped in [nil, 0] as [Int?] {
            let context = ClaimContext(year: today.year,
                                       birthDate: BirthDate(year: birth.year, month: birth.month, day: birth.day),
                                       options: options, yearsSinceWorkStopped: stopped)
            for option in scheme.claimOptions(for: record, context: context, parameters: owner.parameters) {
                let lumpSum = (option.lumpSum ?? 0) > 0
                if let index = routes.firstIndex(where: { $0.id == option.route }) {
                    if !routes[index].ages.contains(option.age) { routes[index].ages.append(option.age) }
                    routes[index].ages.sort()
                    routes[index].paysLumpSum = routes[index].paysLumpSum || lumpSum
                } else {
                    routes.append(Route(id: option.route, label: option.label, ages: [option.age], paysLumpSum: lumpSum))
                }
            }
        }
        return routes
    }

    // MARK: Names

    /// "statutory (a state pension)", for lists of the kinds.
    static func describe(_ kind: PlanPensionKind) -> String {
        switch kind {
        case .statutory: "a state pension"
        case .occupational: "an occupational pension"
        case .basicPension: "a private pension taxed like a state one"
        case .privateAnnuity: "a private annuity"
        default: kind.rawValue
        }
    }

    /// The scheme's name without the explanation in brackets: "INPS".
    static func schemeName(_ id: String, registry: TaxRegistry) -> String {
        guard let name = registry.pensionScheme(id)?.name else { return id }
        guard let bracket = name.range(of: " (") else { return name }
        return String(name[..<bracket.lowerBound])
    }

    /// What a contribution pays into: an account's name and ID, or a scheme's.
    static func target(of contribution: PlanContribution, library: Library, registry: TaxRegistry) -> String {
        if let scheme = contribution.pension {
            return "\(schemeName(scheme.rawValue, registry: registry)) (\(scheme), pension scheme)"
        }
        let name = library.accounts[contribution.account]?.name
        return name.map { "\($0) (\(contribution.account))" } ?? contribution.account.rawValue
    }

    /// "5,000 EUR a year until retirement", "20,000 CHF once in 2030".
    static func timing(of contribution: PlanContribution, currency: CurrencyCode) -> String {
        if let amount = contribution.amount {
            return "\(Format.amount(amount, places: 0)) \(currency) once" + (contribution.year.map { " in \($0)" } ?? "")
        }
        let until = switch contribution.effectiveUntil {
        case .retirement: "retirement"
        case .date(let date): date.description
        }
        return "\(Format.amount(contribution.perYear, places: 0)) \(currency) a year until \(until)"
    }

    // MARK: Wrappers

    /// Whether a wrapper's money is paid out whether it's needed or not:
    /// severance pay when a job ends (locked while working, open as soon as
    /// work stops, as the planner recognises it), a balance its rules pay out
    /// whole (`mustPayOut`), or payouts spread over years (`preferredPayoutYears`).
    static func paysOutByRule(_ rule: WrapperRule) -> Bool {
        func opens(yearsSinceWorkStopped: Int?) -> Bool {
            rule.access(in: WrapperAccessContext(year: 2_000, age: 0, yearsSinceWorkStopped: yearsSinceWorkStopped,
                                                 oldAgePensionAge: nil, contributionYears: 0,
                                                 membershipYears: 0)).isAccessible
        }
        let severance = !opens(yearsSinceWorkStopped: nil) && opens(yearsSinceWorkStopped: 0)
        return severance || rule.mustPayOut != nil || (rule.preferredPayoutYears ?? 0) > 0
    }

    // MARK: Fund types

    /// The fund type the planner works out for a fund with `mix` when the
    /// instrument doesn't say (PLANNER.md, "Portfolio"): more than half in
    /// equity is an equity fund, more than half in real estate a
    /// real-estate fund, at least a quarter in equity a mixed fund, and
    /// anything else another fund.
    static func automaticFundType(for mix: AssetMix) -> FundType {
        let positive = mix.shares.filter { $0.value > 0 }
        let total = positive.values.reduce(Decimal(0), +)
        guard total > 0 else { return .other }
        let equity = (positive[.equity] ?? 0) / total
        if equity > Decimal(string: "0.5")! { return .equity }
        if (positive[.realEstate] ?? 0) / total > Decimal(string: "0.5")! { return .realEstate }
        if equity >= Decimal(string: "0.25")! { return .mixed }
        return .other
    }

    /// Whether an instrument's kind has a fund type (an ETF or a fund).
    static func takesFundType(_ kind: InstrumentKind) -> Bool {
        kind == .etf || kind == .fund
    }

    // MARK: Values

    /// A plan value as TaxKit reads it.
    static func optionValue(_ json: JSONValue) -> OptionValue {
        switch json {
        case .null: .null
        case .bool(let value): .bool(value)
        case .number(let value): .number(NSDecimalNumber(decimal: value).doubleValue)
        case .string(let value): .string(value)
        case .array(let values): .list(values.map(optionValue))
        case .object(let values): .object(values.mapValues(optionValue))
        }
    }

    /// A country code typed in: two letters, in capitals.
    static func country(_ text: String, option: String) throws -> CountryCode {
        let code = CountryCode(text.trimmingCharacters(in: .whitespaces).uppercased())
        guard code.isWellFormed else {
            throw CLIError("\(option) must be a two-letter country code such as DE, not “\(text)”.")
        }
        return code
    }

    /// A currency code typed in: three letters, in capitals.
    static func currency(_ text: String, option: String) throws -> CurrencyCode {
        let code = CurrencyCode(text.trimmingCharacters(in: .whitespaces).uppercased())
        guard code.isWellFormed else {
            throw CLIError("\(option) must be a currency code such as CHF, not “\(text)”.")
        }
        return code
    }
}

/// Writing an edited library back, as the editing commands do.
enum LibraryEdit {
    /// Writes `library` over the loaded one, after backing up the files it
    /// changes, unless `dryRun`; adds what it did to `lines`.
    static func write(_ library: Library, over loaded: LoadedLibrary, label: String, dryRun: Bool,
                      context: CLIContext, lines: inout [String]) throws {
        let paths = library.files(changedFrom: loaded.library).map(\.path).sorted()
        guard !dryRun else {
            lines.append("Dry run: nothing was written" + (paths.isEmpty ? "." : " (\(Format.count(paths.count, "file")) "
                + "would change)."))
            return
        }
        guard !paths.isEmpty else {
            lines.append("Nothing changed.")
            return
        }
        try loaded.checkWritable()
        let backup = try loaded.folder.backup(paths: paths, label: label, date: context.now())
        let saved = try loaded.folder.save(library, previous: loaded.library)
        try loaded.folder.recordResult(of: backup)
        lines.append("Wrote \(Format.count(saved.written.count, "file")): " + saved.written.joined(separator: ", ") + ".")
        lines.append("Backed up the files it changed to \(backup.path).")
    }
}

extension CheckInPriceNeeds {
    /// Adds the currencies plans are in (other than the base currency), so a
    /// check-in fetches their rates: a plan values the accounts in its
    /// currency at the rate on its start date.
    mutating func includePlanCurrencies(of library: Library) {
        let codes = Set(currencies + library.plans.values.compactMap(\.currency)).subtracting([baseCurrency])
        currencies = codes.sorted()
    }
}
