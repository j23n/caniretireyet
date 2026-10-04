import ArgumentParser
import Foundation
import Model
import Planner
import Storage
import TaxKit
import Tracker

/// `retire plan`: runs a plan (the default, ``PlanCommand``), shows its
/// inputs, and changes what the app's plan editor changes: the currency,
/// returns and income yields, the target mix and its changes with age,
/// contributions (into an account or a pension scheme, every year or once),
/// and a pension's kind, paying country and way to claim.
struct PlanGroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "plan",
        abstract: "Run a plan, show its inputs, and change its currency, target mix, contributions, pensions and returns.",
        discussion: """
            retire plan [run] [--fast] [--years]      run the plan, print the answer
            retire plan show                          currency, taxes, pensions, …
            retire plan set --currency CHF            amounts and results in CHF
            retire plan set --income-yield equity=2%  equity's yearly income
            retire plan set --target-mix equity=80%,bonds=20%
                --target-mix-from retirement:equity=60%,bonds=40%
                --target-mix-from 75:equity=40%,bonds=60%
                                                      the mix to rebalance to, by age
            retire plan set --target-mix today        back to today's mix
            retire plan contribution add --account <id> --per-year 5000
            retire plan contribution add --pension <scheme> --amount 20000
                --year 2030                           a buy-in, once
            retire plan contribution remove <n>
            retire plan pension routes <n>            the scheme's ways to claim
            retire plan pension set <n> --kind statutory --source-country DE
            retire plan pension set <n> --claim-route <route>
            retire plan debug [--age today|target|N] [--anonymize]
                [--format md|json] [--output file]    every calculation behind the answer

            Every command takes --plan <id>; without it, the main plan. Pensions and \
            contributions are numbered from 1, as `retire plan show` lists them. \
            Changes are written right away, after a backup of plans/<id>.json \
            (--dry-run shows what they would do), followed by any problem the \
            planner finds with them.
            """,
        subcommands: [PlanCommand.self, PlanShowCommand.self, PlanSetCommand.self, PlanContributionGroup.self,
                      PlanPensionGroup.self, PlanDebugCommand.self],
        defaultSubcommand: PlanCommand.self)
}

// MARK: - show

/// `retire plan show`: the plan's inputs the editing commands change, and
/// its taxes, in words.
struct PlanShowCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show a plan's currency, taxes, pensions, contributions, asset mix and returns.")

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
        let report = PlanInputsReport(plan: document, library: loaded.library, registry: TaxSystems.registry(),
                                      today: context.today)
        if json {
            context.console.print(try JSONOutput.string(report.json))
        } else {
            context.console.print(lines: report.lines())
        }
    }
}

/// A plan's inputs in words (`retire plan show`).
struct PlanInputsReport {
    let plan: PlanDocument
    let library: Library
    let registry: TaxRegistry
    let today: CalendarDate

    var currency: CurrencyCode { plan.effectiveCurrency(base: library.settings.baseCurrency) }

    func lines() -> [String] {
        var lines = ["Plan \(plan.id): \(plan.name)"]
        let base = library.settings.baseCurrency
        lines.append("Currency: \(currency)" + (plan.currency == nil ? " (the library's)" : " (the library's is \(base))"))
        if let issue = PlanEdit.missingRate(for: plan, library: library) { lines.append("  Note: \(issue)") }
        lines.append("Tax residence: " + residence())
        if let citizenships = library.settings.person?.citizenships, !citizenships.isEmpty {
            lines.append("Citizenships: " + citizenships.map(\.rawValue).joined(separator: ", "))
        }

        lines.append("")
        lines.append("Pensions")
        if plan.pensions.isEmpty { lines.append("  None.") }
        for (index, pension) in plan.pensions.enumerated() {
            lines.append("  \(index + 1). " + describe(pension))
        }

        lines.append("")
        lines.append("Contributions")
        if plan.contributions.isEmpty { lines.append("  None.") }
        for (index, contribution) in plan.contributions.enumerated() {
            lines.append("  \(index + 1). \(PlanInputs.target(of: contribution, library: library, registry: registry)) · "
                + PlanInputs.timing(of: contribution, currency: currency))
        }

        lines.append("")
        lines += PlanTargetMix.lines(plan: plan, library: library, registry: registry, today: today)

        lines.append("")
        lines.append("Returns, real, a year")
        var table = TextTable([.left("Class"), .right("Mean"), .right("Median"), .right("Volatility"),
                               .right("Income yield"), .left("Set as")])
        for (assetClass, assumption) in returns() {
            table.add([assetClass.rawValue, Format.percent(assumption.real), Format.percent(assumption.impliedMedianReal),
                       Format.percent(assumption.volatility), Format.percent(assumption.incomeYield),
                       Self.setAs(assumption, isDefault: plan.assumptions.returns[assetClass] == nil)])
        }
        lines += table.lines()
        lines.append("Mean: the average year. Median: the typical year, about what a portfolio rebalanced every year "
            + "grows at; the more volatile the class, the further below the mean.")
        lines.append("Income yield: the part of the return paid as income each year; some countries tax it yearly.")
        return lines
    }

    /// "mean", "median (default)", "mean (median ignored)": what a return
    /// assumption is given by, and where it comes from.
    static func setAs(_ assumption: ReturnAssumption, isDefault: Bool) -> String {
        let given = assumption.setsMeanAndMedian ? "mean (median ignored)"
            : assumption.isGivenByMedian ? "median" : "mean"
        return isDefault ? given + " (default)" : given
    }

    /// "it from 2026 (Italy), generic from 2048", or the default.
    private func residence() -> String {
        let entries = plan.tax.residence.sorted { $0.from < $1.from }
        guard !entries.isEmpty else {
            let system = TaxSystems.residenceSystem(for: library.settings, registry: registry)
            return "not set: \(system.map { "\($0.id) (\($0.name))" } ?? "no system") applies"
        }
        return entries.map { entry in
            let name = registry.system(entry.system.rawValue).map { " (\($0.name))" } ?? " (not a known system)"
            return "\(entry.system) from \(entry.from)\(name)"
        }.joined(separator: ", ")
    }

    /// "State pension from previous country (fixed) · 4,800 a year from 67 · kind statutory · paid from DE".
    private func describe(_ pension: PlanPension) -> String {
        let scheme = pension.scheme.rawValue
        var parts = ["\(pension.name ?? PlanInputs.schemeName(scheme, registry: registry)) (\(scheme))"]
        if pension.scheme == .fixed {
            let amount = pension.perYear.map { Format.amount($0, places: 0) } ?? "?"
            parts.append("\(amount) a year from \(pension.fromAge.map(String.init) ?? "?")")
        } else {
            switch pension.effectiveClaim {
            case .earliest: parts.append("claimed as early as possible")
            case .age(let age): parts.append("claimed at \(age)")
            }
            if let route = pension.claimRoute {
                let routes = PlanInputs.claimRoutes(for: pension, birthDate: library.settings.person?.birthDate,
                                                    today: today, registry: registry)
                parts.append("way to claim \(route)" + (routes.first { $0.id == route }.map { " (\($0.label))" } ?? ""))
            }
        }
        if let kind = pension.kind { parts.append("kind \(kind)") }
        if let country = pension.sourceCountry { parts.append("paid from \(country)") }
        if pension.effectiveTaxedIn == .source { parts.append(PlanInputs.sourceTaxNote(for: pension, registry: registry)) }
        return parts.joined(separator: " · ")
    }

    /// Each asset class's assumption, the plan's or the default, in the
    /// usual order, then any other the plan names.
    private func returns() -> [(AssetClass, ReturnAssumption)] {
        let classes = AssetClass.knownValues.filter { $0 != .other }
            + plan.assumptions.returns.keys.filter { !AssetClass.knownValues.contains($0) }.sorted()
        return classes.compactMap { assetClass in
            plan.assumptions.returnAssumption(for: assetClass).map { (assetClass, $0) }
        }
    }

    var json: JSON {
        JSON(plan: plan.id.rawValue, name: plan.name, currency: currency.rawValue, ownCurrency: plan.currency?.rawValue,
             residence: plan.tax.residence.map { JSON.Residence(from: $0.from, system: $0.system.rawValue) },
             pensions: plan.pensions.enumerated().map { index, pension in
                 JSON.Pension(number: index + 1, scheme: pension.scheme.rawValue, name: pension.name,
                              claim: pension.claim.map { $0 == .earliest ? "earliest" : "\($0.age ?? 0)" },
                              claimRoute: pension.claimRoute, kind: pension.kind?.rawValue,
                              sourceCountry: pension.sourceCountry?.rawValue, taxedIn: pension.taxedIn?.rawValue,
                              fromAge: pension.fromAge, perYear: pension.perYear?.fileString)
             },
             contributions: plan.contributions.enumerated().map { index, contribution in
                 JSON.Contribution(number: index + 1,
                                   account: contribution.pension == nil ? contribution.account.rawValue : nil,
                                   pension: contribution.pension?.rawValue,
                                   perYear: contribution.isOneOff ? nil : contribution.perYear.fileString,
                                   until: contribution.isOneOff ? nil : contribution.until.map(Self.until),
                                   amount: contribution.amount?.fileString, year: contribution.year)
             },
             returns: Dictionary(uniqueKeysWithValues: returns().map { assetClass, assumption in
                 (assetClass.rawValue, JSON.Return(
                     real: (assumption.realAsWritten ?? Format.rounded(assumption.real, places: 6)).fileString,
                     volatility: assumption.volatility.fileString,
                     incomeYield: assumption.incomeYield?.fileString,
                     median: (assumption.isGivenByMedian ? assumption.impliedMedianReal
                         : Format.rounded(assumption.impliedMedianReal, places: 6)).fileString,
                     givenAs: assumption.isGivenByMedian ? "median" : "mean",
                     isDefault: plan.assumptions.returns[assetClass] == nil))
             }),
             assetMix: PlanTargetMix.json(plan: plan, library: library, registry: registry, today: today))
    }

    private static func until(_ end: PhaseEnd) -> String {
        switch end {
        case .retirement: "retirement"
        case .date(let date): date.description
        }
    }

    struct JSON: Encodable {
        struct Residence: Encodable {
            var from: Int
            var system: String
        }

        struct Pension: Encodable {
            var number: Int
            var scheme: String
            var name: String?
            var claim: String?
            var claimRoute: String?
            var kind: String?
            var sourceCountry: String?
            var taxedIn: String?
            var fromAge: Int?
            var perYear: String?
        }

        struct Contribution: Encodable {
            var number: Int
            var account: String?
            var pension: String?
            var perYear: String?
            var until: String?
            var amount: String?
            var year: Int?
        }

        struct Return: Encodable {
            /// The mean (arithmetic) real return: as written, or derived from
            /// the median, to 6 decimals.
            var real: String
            var volatility: String
            var incomeYield: String?
            /// The median real return: as written, or derived from the mean.
            var median: String
            /// `mean` or `median`: what the plan, or the default, gives.
            var givenAs: String
            /// Whether it's the default (the plan sets nothing for the class).
            var isDefault: Bool
        }

        var plan: String
        var name: String
        /// The plan's currency: its own, else the library's.
        var currency: String
        /// As written in the plan; absent for the library's.
        var ownCurrency: String?
        var residence: [Residence]
        var pensions: [Pension]
        var contributions: [Contribution]
        var returns: [String: Return]
        /// The target mix, its changes with age, and today's mix.
        var assetMix: PlanTargetMix.JSON
    }
}

// MARK: - set

/// `retire plan set`: the plan's currency, return assumptions, income
/// yields and target mix.
struct PlanSetCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a plan's currency, its target mix, or an asset class's return, volatility or income yield.",
        discussion: """
            --currency CHF puts the plan's amounts and results in CHF; --currency library goes back to the \
            library's base currency. The library needs exchange rates between the two to value your accounts. \
            --return equity=4.5% (or 0.045) sets equity's expected real return as its mean, the average \
            year; --median-return crypto=0% sets it as its median, the typical year, and the mean follows \
            from the median and the volatility. --volatility crypto=70% sets the volatility, keeping \
            whichever of the two was given. --return equity=default goes back to the default. \
            --income-yield equity=0.02 (or 2%) is the part of equity's return paid as income each year, which \
            some countries tax yearly; equity=none removes it. Repeat each for more classes. What equals the \
            default isn't written to the plan.

            --target-mix equity=80%,bonds=20% (or repeated --target equity=0.8) is the mix the ordinary \
            (taxable) accounts are rebalanced to every year: new money buys what's below it, withdrawals sell \
            what's above, and the rest is sold and bought, with tax on gains. It must add up to 100%. \
            --target-mix today removes it and any changes with age: each account is rebalanced back to its own \
            mix today. --target-mix-from 55:equity=60%,bonds=40% changes it from an age, and \
            --target-mix-from retirement:… from the year you retire, whatever age the plan finds; repeat it for \
            each change, in order (the steps given replace the plan's), or give --target-mix-from none to remove \
            them. A change already passed applies from the start. Pension funds and other tax-advantaged \
            accounts keep their own mix.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Option(help: ArgumentHelp("The plan's currency, e.g. CHF, or `library` for the library's.", valueName: "code"))
    var currency: String?

    @Option(name: .customLong("return"),
            help: ArgumentHelp("An asset class's expected real return as its mean, e.g. equity=4.5%, or default.",
                               valueName: "class=mean"))
    var meanReturn: [String] = []

    @Option(name: .customLong("median-return"),
            help: ArgumentHelp("An asset class's expected real return as its median, e.g. crypto=0%.",
                               valueName: "class=median"))
    var medianReturn: [String] = []

    @Option(help: ArgumentHelp("An asset class's volatility, e.g. crypto=70%.", valueName: "class=volatility"))
    var volatility: [String] = []

    @Option(help: ArgumentHelp("An asset class's income yield, e.g. equity=0.02, 2%, or none.",
                               valueName: "class=yield"))
    var incomeYield: [String] = []

    @Option(help: ArgumentHelp("The mix the ordinary accounts are rebalanced to, e.g. equity=70%,bonds=30%, or "
                                   + "today for today's mix.", valueName: "mix"))
    var targetMix: String?

    @Option(help: ArgumentHelp("One class of the target mix instead, e.g. equity=0.7; repeat for each.",
                               valueName: "class=share"))
    var target: [String] = []

    @Option(help: ArgumentHelp("A change of the target mix from an age or retirement, e.g. 55:equity=60%,bonds=40%; "
                                   + "repeat for each, in order, or none.", valueName: "age:mix"))
    var targetMixFrom: [String] = []

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    /// What `--target-mix` or `--target` sets: today's mix (none), or a mix.
    enum TargetChange: Equatable {
        case today
        case mix(AssetMix)
    }

    /// The target mix asked for, if any.
    func targetChange() throws -> TargetChange? {
        if let targetMix {
            guard target.isEmpty else { throw ValidationError("Give the target mix with --target-mix or --target, not both.") }
            if targetMix.lowercased() == "today" { return .today }
            return .mix(try PlanTargetMix.mix(targetMix, option: "--target-mix"))
        }
        guard !target.isEmpty else { return nil }
        return .mix(try PlanTargetMix.mix(entries: target, option: "--target"))
    }

    func validate() throws {
        guard currency != nil || !incomeYield.isEmpty || !meanReturn.isEmpty || !medianReturn.isEmpty
            || !volatility.isEmpty || targetMix != nil || !target.isEmpty || !targetMixFrom.isEmpty else {
            throw ValidationError("Say what to set: --currency, --return, --median-return, --volatility, "
                + "--income-yield, --target-mix or --target-mix-from.")
        }
        _ = try targetChange()
        if !targetMixFrom.isEmpty { _ = try PlanTargetMix.steps(targetMixFrom, option: "--target-mix-from") }
        if let currency, currency.lowercased() != "library", !CurrencyCode(currency.uppercased()).isWellFormed {
            throw ValidationError("--currency must be a currency code such as CHF, or library.")
        }
        for entry in incomeYield { _ = try Self.yield(entry) }
        _ = try returnChanges()
    }

    /// What `--return`, `--median-return` and `--volatility` change, per class.
    struct ReturnChange {
        /// `nil`: the default's.
        var mean: Decimal??
        var median: Decimal?
        var volatility: Decimal?
    }

    /// The return changes, by class in the usual order.
    func returnChanges() throws -> [(AssetClass, ReturnChange)] {
        var changes: [AssetClass: ReturnChange] = [:]
        for entry in meanReturn {
            let (assetClass, value) = try Self.share(entry, option: "--return", allowsDefault: true)
            if let value, value <= -1 { throw ValidationError("--return: a real return must be above -100%.") }
            if value == nil, PlanAssumptions.defaultReturns[assetClass] == nil {
                throw ValidationError("--return: \(assetClass) has no default return.")
            }
            changes[assetClass, default: ReturnChange()].mean = .some(value)
        }
        for entry in medianReturn {
            let (assetClass, value) = try Self.share(entry, option: "--median-return", allowsDefault: false)
            guard let value, value > -1 else {
                throw ValidationError("--median-return: a real return must be above -100%.")
            }
            if changes[assetClass]?.mean != nil {
                throw ValidationError("Give \(assetClass)'s return as its mean (--return) or its median "
                    + "(--median-return), not both.")
            }
            changes[assetClass, default: ReturnChange()].median = value
        }
        for entry in volatility {
            let (assetClass, value) = try Self.share(entry, option: "--volatility", allowsDefault: false)
            guard let value, value >= 0 else { throw ValidationError("--volatility can't be negative.") }
            changes[assetClass, default: ReturnChange()].volatility = value
        }
        return AssetClass.knownValues.compactMap { assetClass in changes[assetClass].map { (assetClass, $0) } }
    }

    /// `equity=0.045` (or `4.5%`, or `default` when `allowsDefault`) as a
    /// class and a share; `nil` for `default`.
    static func share(_ entry: String, option: String, allowsDefault: Bool) throws -> (AssetClass, Decimal?) {
        let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty else {
            throw ValidationError("\(option) takes class=value, e.g. equity=0.045, not “\(entry)”.")
        }
        let assetClass = AssetClass(parts[0])
        guard AssetClass.knownValues.contains(assetClass) else {
            throw ValidationError("\(option): “\(parts[0])” isn't an asset class ("
                + AssetClass.knownValues.map(\.rawValue).joined(separator: ", ") + ").")
        }
        if allowsDefault, parts[1].lowercased() == "default" { return (assetClass, nil) }
        let isPercent = parts[1].hasSuffix("%")
        guard let number = Decimal(fileString: isPercent ? String(parts[1].dropLast()) : parts[1]) else {
            throw ValidationError("\(option): “\(parts[1])” isn't a number written like 0.045 or 4.5%.")
        }
        return (assetClass, isPercent ? number / 100 : number)
    }

    /// `equity=0.02` (or `2%`, or `none`) as a class and a yield.
    static func yield(_ entry: String) throws -> (AssetClass, Decimal?) {
        let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty else {
            throw ValidationError("--income-yield takes class=yield, e.g. equity=0.02, not “\(entry)”.")
        }
        let assetClass = AssetClass(parts[0])
        guard AssetClass.knownValues.contains(assetClass) else {
            throw ValidationError("--income-yield: “\(parts[0])” isn't an asset class ("
                + AssetClass.knownValues.map(\.rawValue).joined(separator: ", ") + ").")
        }
        if parts[1].lowercased() == "none" { return (assetClass, nil) }
        let isPercent = parts[1].hasSuffix("%")
        guard let number = Decimal(fileString: isPercent ? String(parts[1].dropLast()) : parts[1]) else {
            throw ValidationError("--income-yield: “\(parts[1])” isn't a number written like 0.02 or 2%.")
        }
        let share = isPercent ? number / 100 : number
        guard share >= 0, share <= 1 else {
            throw ValidationError("--income-yield: \(parts[0])'s yield must be between 0 and 100%.")
        }
        return (assetClass, share)
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let (loaded, original) = try PlanEdit.load(options, plan: plan, context: context)
        var edited = original
        var lines: [String] = []
        var sections: [PlanSection] = []
        let base = loaded.library.settings.baseCurrency
        if let currency {
            let code = currency.lowercased() == "library" ? nil : CurrencyCode(currency.uppercased())
            edited.currency = code == base ? nil : code
            lines.append("Currency: \(edited.effectiveCurrency(base: base))"
                + (edited.currency == nil ? " (the library's)." : "."))
            if let issue = PlanEdit.missingRate(for: edited, library: loaded.library) { lines.append("  Note: \(issue)") }
            sections.append(.tax)
        }
        for (assetClass, change) in try returnChanges() {
            var assumption = edited.assumptions.returnAssumption(for: assetClass)
                ?? ReturnAssumption(real: 0, volatility: 0)
            if case .some(let mean) = change.mean {
                if let mean {
                    assumption.real = mean
                } else if let fallback = PlanAssumptions.defaultReturns[assetClass] {
                    let yield = assumption.incomeYield
                    assumption = fallback
                    assumption.incomeYield = yield
                }
            }
            if let median = change.median { assumption.medianReal = median }
            if let volatility = change.volatility { assumption.volatility = volatility }
            edited.assumptions.setReturnAssumption(assumption, for: assetClass)
            let given = assumption.isGivenByMedian
                ? "median \(Format.percent(assumption.impliedMedianReal)) (mean \(Format.percent(assumption.real)))"
                : "mean \(Format.percent(assumption.real)) (median \(Format.percent(assumption.impliedMedianReal)))"
            lines.append("Return of \(assetClass): \(given) at \(Format.percent(assumption.volatility)) volatility"
                + (edited.assumptions.returns[assetClass] == nil ? ", the default." : "."))
            sections.append(.assumptions)
        }
        for entry in incomeYield {
            let (assetClass, share) = try Self.yield(entry)
            var assumption = edited.assumptions.returnAssumption(for: assetClass)
                ?? ReturnAssumption(real: 0, volatility: 0)
            assumption.incomeYield = share
            edited.assumptions.setReturnAssumption(assumption, for: assetClass)
            lines.append("Income yield of \(assetClass): " + (share.map { Format.percent($0) } ?? "none") + ".")
            sections.append(.assumptions)
        }
        switch try targetChange() {
        case .today?:
            edited.portfolio.targetMix = nil
            edited.portfolio.targetMixByAge = []
            lines.append("Target mix: today's. Each ordinary account is rebalanced back to its own mix today.")
            sections.append(.portfolio)
        case .mix(let mix)?:
            edited.portfolio.targetMix = mix
            lines.append("Target mix: \(PlanTargetMix.describe(mix)).")
            sections.append(.portfolio)
        case nil:
            break
        }
        if !targetMixFrom.isEmpty {
            edited.portfolio.targetMixByAge = try PlanTargetMix.steps(targetMixFrom, option: "--target-mix-from")
            if edited.portfolio.targetMixByAge.isEmpty { lines.append("Target mix by age: no changes.") }
            for step in edited.portfolio.targetMixByAge {
                lines.append("From \(PlanTargetMix.describe(step.fromAge)): \(PlanTargetMix.describe(step.mix)).")
            }
            sections.append(.portfolio)
        }
        try PlanEdit.write(edited, replacing: original, over: loaded, sections: sections, dryRun: dryRun,
                           context: context, lines: &lines)
        context.console.print(lines: lines)
    }
}

// MARK: - contribution

/// `retire plan contribution`: add and remove a plan's contributions.
struct PlanContributionGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contribution",
        abstract: "Add or remove a plan's contribution into an account or a pension scheme.",
        subcommands: [PlanContributionAddCommand.self, PlanContributionRemoveCommand.self])
}

/// `retire plan contribution add`: a payment into an account or a pension
/// scheme (a buy-in), every year while working or once.
struct PlanContributionAddCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a contribution: into an account or a pension scheme, every year or once.",
        discussion: """
            Into an account (--account <id>) or a pension scheme (--pension <scheme>, a buy-in: the tax \
            system decides what it adds to the pension and any tax relief). Every year while working \
            (--per-year, until retirement or --until <date>) or once (--amount in --year). Amounts are \
            in the plan's currency, in today's money.
            """)

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Option(help: ArgumentHelp("The account paid into.", valueName: "id"))
    var account: String?

    @Option(help: ArgumentHelp("The pension scheme paid into instead, e.g. ch.bvg.", valueName: "scheme"))
    var pension: String?

    @Option(help: ArgumentHelp("The amount paid every year while working.", valueName: "amount"))
    var perYear: String?

    @Option(help: ArgumentHelp("When yearly payments stop: retirement (the default) or a date.", valueName: "date"))
    var until: String?

    @Option(help: ArgumentHelp("An amount paid once, in --year.", valueName: "amount"))
    var amount: String?

    @Option(help: ArgumentHelp("The year of a one-off --amount.", valueName: "year"))
    var year: Int?

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    func validate() throws {
        guard (account == nil) != (pension == nil) else {
            throw ValidationError("Say where it goes: --account <id> or --pension <scheme>, one of them.")
        }
        guard (perYear == nil) != (amount == nil) else {
            throw ValidationError("Say how it's paid: --per-year <amount> or --amount <amount> --year <year>.")
        }
        if amount != nil, year == nil { throw ValidationError("A one-off --amount needs its --year.") }
        if amount == nil, year != nil { throw ValidationError("--year is for a one-off --amount.") }
        if amount != nil, until != nil { throw ValidationError("--until is for yearly payments (--per-year).") }
        for (value, option) in [(perYear, "--per-year"), (amount, "--amount")] {
            if let decimal = try TradesAddCommand.decimal(value, option: option), decimal <= 0 {
                throw ValidationError("\(option) must be more than 0.")
            }
        }
        if let until, until != "retirement" { _ = try parseDate(until, option: "--until") }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let (loaded, original) = try PlanEdit.load(options, plan: plan, context: context)
        let registry = TaxSystems.registry()
        var contribution: PlanContribution
        if let pension {
            guard registry.pensionScheme(pension) != nil else {
                var schemes: [String] = []
                for scheme in registry.systems.flatMap(\.pensionSchemes)
                where scheme.id != FixedPensionScheme.schemeID && !schemes.contains(scheme.id) {
                    schemes.append(scheme.id)
                }
                throw CLIError("There's no pension scheme \"\(pension)\". Schemes: \(schemes.joined(separator: ", ")).")
            }
            contribution = PlanContribution(pension: PensionSchemeID(pension), perYear: 0)
        } else {
            _ = try loaded.account(account ?? "")
            contribution = PlanContribution(account: AccountID(account ?? ""), perYear: 0)
        }
        if let amount = try TradesAddCommand.decimal(amount, option: "--amount"), let year {
            contribution.amount = amount
            contribution.year = year
        } else {
            contribution.perYear = try TradesAddCommand.decimal(perYear, option: "--per-year") ?? 0
            if let until, until != "retirement" { contribution.until = .date(try parseDate(until, option: "--until")!) }
        }
        var edited = original
        edited.contributions.append(contribution)
        let currency = edited.effectiveCurrency(base: loaded.library.settings.baseCurrency)
        var lines = ["Contribution \(edited.contributions.count): "
            + PlanInputs.target(of: contribution, library: loaded.library, registry: registry) + " · "
            + PlanInputs.timing(of: contribution, currency: currency) + "."]
        try PlanEdit.write(edited, replacing: original, over: loaded, sections: [.contributions], dryRun: dryRun,
                           context: context, lines: &lines)
        context.console.print(lines: lines)
    }
}

/// `retire plan contribution remove <n>`.
struct PlanContributionRemoveCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a plan's contribution, by its number in `retire plan show`.")

    @Argument(help: ArgumentHelp("The contribution's number, from 1.", valueName: "n"))
    var number: Int

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let (loaded, original) = try PlanEdit.load(options, plan: plan, context: context)
        let index = try PlanEdit.index(number, count: original.contributions.count, of: "contribution")
        var edited = original
        let removed = edited.contributions.remove(at: index)
        let currency = original.effectiveCurrency(base: loaded.library.settings.baseCurrency)
        var lines = ["Removed contribution \(number): "
            + PlanInputs.target(of: removed, library: loaded.library, registry: TaxSystems.registry()) + " · "
            + PlanInputs.timing(of: removed, currency: currency) + "."]
        try PlanEdit.write(edited, replacing: original, over: loaded, sections: [.contributions], dryRun: dryRun,
                           context: context, lines: &lines)
        context.console.print(lines: lines)
    }
}

// MARK: - pension

/// `retire plan pension`: a pension's kind, paying country and way to claim.
struct PlanPensionGroup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pension",
        abstract: "List a pension's ways to claim, or set its kind, paying country and way to claim.",
        subcommands: [PlanPensionRoutesCommand.self, PlanPensionSetCommand.self])
}

/// `retire plan pension routes <n>`: the ways its scheme can be claimed.
struct PlanPensionRoutesCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "routes",
        abstract: "List the ways a pension's scheme can be claimed.",
        discussion: """
            The scheme's claim options for the pension's details as they are (its options in the plan), \
            asked as if you were still working and as if work had just stopped. A route that needs more \
            contributions than the details say yet isn't listed; a plan run warns about a claim route the \
            scheme never offers.
            """)

    @Argument(help: ArgumentHelp("The pension's number, from 1.", valueName: "n"))
    var number: Int

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Flag(help: "Print JSON.")
    var json = false

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let loaded = try options.load(in: context)
        let document = try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library)
        let index = try PlanEdit.index(number, count: document.pensions.count, of: "pension")
        let pension = document.pensions[index]
        let routes = PlanInputs.claimRoutes(for: pension, birthDate: loaded.library.settings.person?.birthDate,
                                            today: context.today, registry: TaxSystems.registry())
        if json {
            struct Row: Encodable {
                var route: String
                var label: String
                var ages: [Int]
                var lumpSum: Bool
                var chosen: Bool
            }
            context.console.print(try JSONOutput.string(routes.map {
                Row(route: $0.id, label: $0.label, ages: $0.ages, lumpSum: $0.paysLumpSum,
                    chosen: $0.id == pension.claimRoute)
            }))
            return
        }
        let name = pension.name ?? PlanInputs.schemeName(pension.scheme.rawValue, registry: TaxSystems.registry())
        var lines = ["Ways to claim pension \(number), \(name) (\(pension.scheme))"]
        guard !routes.isEmpty else {
            lines.append("  The scheme lists none with the pension's details as they are.")
            context.console.print(lines: lines)
            return
        }
        var table = TextTable([.left("Route"), .left("Label"), .left("Ages"), .left("")])
        for route in routes {
            let ages = route.ages.count == 1 ? "\(route.ages[0])" : "\(route.ages[0])–\(route.ages[route.ages.count - 1])"
            let notes = [route.paysLumpSum ? "lump sum" : nil, route.id == pension.claimRoute ? "chosen" : nil]
            table.add([route.id, route.label, ages, notes.compactMap { $0 }.joined(separator: ", ")])
        }
        lines += table.lines()
        lines.append(pension.claimRoute == nil ? "The plan takes the first offered at the age it claims."
            : "The plan claims it by \(pension.claimRoute!).")
        context.console.print(lines: lines)
    }
}

/// `retire plan pension set <n>`: its kind, paying country, way to claim.
struct PlanPensionSetCommand: RetireSubcommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a pension's kind, paying country, way to claim and where it's taxed.",
        discussion: """
            --kind says what a pension from a statement is, for tax systems that tax kinds differently: \
            statutory (a state pension), occupational, basicPension (a private pension taxed like a state \
            one) or privateAnnuity; none to leave it to the scheme. --source-country is the paying country \
            (none to clear). --claim-route picks one of the scheme's ways to claim, as `retire plan pension \
            routes` lists them; default takes the first offered at the age. --taxed-in source has the \
            paying country tax it, by its rules when the CLI has them (else enter the pension after that tax); \
            residence (the default) taxes it where you live.
            """)

    @Argument(help: ArgumentHelp("The pension's number, from 1.", valueName: "n"))
    var number: Int

    @OptionGroup var options: LibraryOptions

    @Option(help: ArgumentHelp("The plan, plans/<id>.json. Default: the main plan.", valueName: "id"))
    var plan: String?

    @Option(help: ArgumentHelp("statutory, occupational, basicPension, privateAnnuity, or none.", valueName: "kind"))
    var kind: String?

    @Option(help: ArgumentHelp("The paying country, e.g. DE, or none.", valueName: "country"))
    var sourceCountry: String?

    @Option(help: ArgumentHelp("A route from `retire plan pension routes`, or default.", valueName: "route"))
    var claimRoute: String?

    @Option(help: ArgumentHelp("Who taxes it: residence (where you live) or source (the paying country).",
                               valueName: "where"))
    var taxedIn: String?

    @Flag(help: "Show what would change; write nothing.")
    var dryRun = false

    func validate() throws {
        guard kind != nil || sourceCountry != nil || claimRoute != nil || taxedIn != nil else {
            throw ValidationError("Say what to set: --kind, --source-country, --claim-route or --taxed-in.")
        }
        if let taxedIn, ![TaxedIn.residence.rawValue, TaxedIn.source.rawValue].contains(taxedIn) {
            throw ValidationError("--taxed-in must be residence or source.")
        }
        if let kind, kind != "none", !PlanPensionKind.knownValues.contains(PlanPensionKind(kind)) {
            throw ValidationError("--kind must be one of "
                + PlanPensionKind.knownValues.map(\.rawValue).joined(separator: ", ") + ", or none.")
        }
        if let sourceCountry, sourceCountry.lowercased() != "none" {
            _ = try PlanInputs.country(sourceCountry, option: "--source-country")
        }
    }

    mutating func run() async throws {
        try await run(in: .live())
    }

    func run(in context: CLIContext) async throws {
        let (loaded, original) = try PlanEdit.load(options, plan: plan, context: context)
        let index = try PlanEdit.index(number, count: original.pensions.count, of: "pension")
        var pension = original.pensions[index]
        var lines: [String] = []
        if let kind {
            pension.kind = kind == "none" ? nil : PlanPensionKind(kind)
            lines.append("Kind: " + (pension.kind.map { "\($0) (\(PlanInputs.describe($0)))" } ?? "the scheme's") + ".")
        }
        if let sourceCountry {
            pension.sourceCountry = sourceCountry.lowercased() == "none" ? nil
                : try PlanInputs.country(sourceCountry, option: "--source-country")
            lines.append("Paying country: \(pension.sourceCountry?.rawValue ?? "not set").")
        }
        if let claimRoute {
            let route = claimRoute.trimmingCharacters(in: .whitespaces)
            pension.claimRoute = route == "default" || route.isEmpty ? nil : route
            if let chosen = pension.claimRoute {
                let routes = PlanInputs.claimRoutes(for: pension, birthDate: loaded.library.settings.person?.birthDate,
                                                    today: context.today, registry: TaxSystems.registry())
                if let known = routes.first(where: { $0.id == chosen }) {
                    lines.append("Way to claim: \(chosen) (\(known.label)).")
                } else {
                    lines.append("Way to claim: \(chosen).")
                    lines.append("  Note: the scheme doesn't list it with the pension's details as they are"
                        + (routes.isEmpty ? "." : " (it lists \(routes.map(\.id).joined(separator: ", "))).")
                        + " A plan run warns if it's never offered.")
                }
            } else {
                lines.append("Way to claim: the first offered at the age.")
            }
        }
        if let taxedIn {
            pension.taxedIn = taxedIn == TaxedIn.residence.rawValue ? nil : TaxedIn(taxedIn)
        }
        if taxedIn != nil || (sourceCountry != nil && pension.effectiveTaxedIn == .source) {
            lines.append(pension.effectiveTaxedIn == .source
                ? "T" + PlanInputs.sourceTaxNote(for: pension, registry: TaxSystems.registry()).dropFirst() + "."
                : "Taxed where you live.")
        }
        var edited = original
        edited.pensions[index] = pension
        let name = pension.name ?? PlanInputs.schemeName(pension.scheme.rawValue, registry: TaxSystems.registry())
        lines.insert("Pension \(number), \(name) (\(pension.scheme)):", at: 0)
        try PlanEdit.write(edited, replacing: original, over: loaded, sections: [.pensions], dryRun: dryRun,
                           context: context, lines: &lines)
        context.console.print(lines: lines)
    }
}

// MARK: - Shared

/// Loading the plan an editing command changes, and writing it back.
enum PlanEdit {
    /// The library and the plan: the one asked for, or the main plan.
    static func load(_ options: LibraryOptions, plan: String?, context: CLIContext) throws
        -> (LoadedLibrary, PlanDocument) {
        let loaded = try options.load(in: context)
        return (loaded, try PlanCommand.plan(plan.map { PlanID($0) }, in: loaded.library))
    }

    /// The position of item `number` (from 1) of `count`.
    static func index(_ number: Int, count: Int, of item: String) throws -> Int {
        guard count > 0 else { throw CLIError("The plan has no \(item)s.") }
        guard (1...count).contains(number) else {
            throw CLIError("There's no \(item) \(number): the plan has \(Format.count(count, item)), numbered from 1.")
        }
        return number - 1
    }

    /// Writes `plan` in place of `original` (after a backup, unless
    /// `dryRun`), then adds the planner's new problems in `sections`.
    static func write(_ plan: PlanDocument, replacing original: PlanDocument, over loaded: LoadedLibrary,
                      sections: [PlanSection], dryRun: Bool, context: CLIContext, lines: inout [String]) throws {
        var library = loaded.library
        library.plans[plan.id] = plan
        try LibraryEdit.write(library, over: loaded, label: "plan", dryRun: dryRun, context: context, lines: &lines)
        let registry = TaxSystems.registry()
        let options = PlannerOptions(today: context.today)
        let before = Set(Planner.validate(plan: original, library: loaded.library, registry: registry, options: options))
        let after = Planner.validate(plan: plan, library: library, registry: registry, options: options)
        for issue in after where sections.contains(issue.section) && !before.contains(issue) {
            lines.append("  \(issue.isError ? "error  " : "warning") \(issue.message)")
        }
    }

    /// Why a plan in another currency can't value the library's accounts:
    /// no exchange rate at all between it and the base currency.
    static func missingRate(for plan: PlanDocument, library: Library) -> String? {
        let base = library.settings.baseCurrency
        guard let currency = plan.currency, currency != base else { return nil }
        let fx = FXTable(library: library)
        guard fx.quote(from: base, to: currency, on: CalendarDate(year: 9_999, month: 12, day: 31)!) == nil else {
            return nil
        }
        return "the library has no exchange rate between \(base) and \(currency), so the plan can't value your "
            + "accounts in \(currency). Add rates with `retire prices`."
    }
}
