import Foundation
import Model
import Testing
import TestSupport

/// Every key a type writes must be in its `knownKeys`, or Storage would
/// treat the app's own data as unknown and duplicate it. And every known key
/// must be written by a fully populated value, so the list stays accurate.
struct KnownKeysTests {
    private static let position = Position(instrument: "vwce", quantity: d("412.5"), costBasis: d("48200"))
    private static let valuation = Valuation(
        account: "directa", date: "2026-09-30", balance: d("1"), cash: d("312.1"), positions: [position],
        flow: d("1500"), note: "n", source: .manual)
    private static let trade = Trade(
        account: "directa", date: "2026-03-12", id: "k3q7vz2m", type: .buy, instrument: "vwce", quantity: 10,
        price: d("127.35"), currency: .eur, amount: d("-1278.5"), fees: 5, tax: 0, cost: 1, ratio: 1, note: "n",
        source: .manual, settlement: .external)
    private static let summary = HeadlineSummary(confidence: d("0.9"), earliestAge: 54, successAtTarget: d("0.86"),
                                                 readiness: d("0.58"))
    private static let format = ImportFormat(
        date: ImportDateFormat(pattern: "dd/MM/yyyy", monthOnly: .start, timeZone: "Europe/Rome"),
        number: ImportNumberFormat(decimal: ",", thousands: ".", percent: false), empty: .zero,
        liabilitySign: .asWritten, amountSign: .fromType)
    /// A contribution with every key, though a real one has a yearly or a
    /// one-off amount.
    private static var contribution: PlanContribution {
        var contribution = PlanContribution(account: "fondo-pensione", perYear: 5000, until: .date("2040-12-31"))
        contribution.amount = 20_000
        contribution.year = 2030
        return contribution
    }

    private static let plan = PlanDocument(
        id: "base", name: "Base", retirement: PlanRetirement(age: .age(55)), endAge: 95,
        tax: PlanTax(investmentRate: d("0.26"), wealthRate: d("0.002"), wealthAllowance: 50_000),
        work: [WorkPhase(name: "Employee", from: "2026-01-01", until: .retirement, netIncome: 40_000,
                         realGrowth: d("0.01"))],
        spending: PlanSpending(working: 36000, retired: 36000, phases: [SpendingPhase(fromAge: 75, factor: d("0.9"))],
                               flexible: FlexibleSpending(enabled: true, cut: d("0.15"), floor: d("0.75"),
                                                          upperGuardrail: d("0.25"), lowerGuardrail: d("0.15"))),
        pensions: [PlanPension(name: "State pension", fromAge: 67, perYear: 4800)],
        income: [PlanIncome(name: "Rent", from: .age(45), untilAge: 85, perYear: 9600)],
        contributions: [contribution],
        events: [PlanEvent(name: "I", timing: .age(62), amount: 150_000, probability: d("0.8"))],
        portfolio: PlanPortfolio(start: .latestCheckIn, unrealizedGainShare: d("0.2"), exclude: ["gold-coins"],
                                 targetMix: [.equity: 1],
                                 targetMixByAge: [TargetMixStep(fromAge: .retirement, mix: [.bonds: 1])]),
        assumptions: PlanAssumptions(inflation: d("0.02"), returns: [.equity: ReturnAssumption(real: d("0.045"), volatility: d("0.17"))],
                                     correlations: CorrelationTable([.equity: [.bonds: d("0.1")]])),
        simulation: PlanSimulation(runs: 2000, seed: 1, confidence: d("0.9")))

    /// A fully populated value of every type with known keys.
    private static var samples: [(any Encodable, Set<String>)] { [
        (LibrarySettings(person: Person(name: "Me", birthDate: "1988-04-12"), taxResidence: .it, mainPlan: "base",
                         inflationIndex: .hicpEA), LibrarySettings.knownKeys),
        (Person(name: "Me", birthDate: "1988-04-12"), Person.knownKeys),
        (Account(id: "a", name: "A", kind: .cash, currency: .eur, opened: "2020-01-01", closed: "2025-01-01",
                 institution: "Bank", country: .it, valuation: .balance, assetClasses: .single(.cash),
                 availableFromAge: 60, includeIn: IncludeIn(netWorth: true, plan: false),
                 successor: "b", tags: ["t"], notes: "n"), Account.knownKeys),
        (IncludeIn(netWorth: true, plan: false), IncludeIn.knownKeys),
        (Instrument(id: "vwce", name: "V", kind: .etf, currency: .eur, unit: .share, assetClasses: .single(.equity),
                    isin: "X", ticker: "V", priceSource: PriceSource(provider: .yahoo, symbol: "V")),
         Instrument.knownKeys),
        (PriceSource(provider: .yahoo, symbol: "V"), PriceSource.knownKeys),
        (MonthFile(month: "2026-09", trades: [trade]), MonthFile.knownKeys),
        (trade, Trade.knownKeys),
        (valuation, Valuation.knownKeys),
        (position, Position.knownKeys),
        (PriceRecord(instrument: "vwce", date: "2026-09-30", price: 1, currency: .eur, source: .yahoo), PriceRecord.knownKeys),
        (FXRecord(base: .eur, quote: .usd, date: "2026-09-30", rate: 1, source: .ecb), FXRecord.knownKeys),
        (IndexRecord(index: .hicpIT, date: "2026-08-31", value: 1, source: .eurostat), IndexRecord.knownKeys),
        (plan, PlanDocument.knownKeys),
        (plan.retirement, PlanRetirement.knownKeys),
        (plan.tax, PlanTax.knownKeys),
        (plan.work[0], WorkPhase.knownKeys),
        (plan.spending, PlanSpending.knownKeys),
        (plan.spending.phases[0], SpendingPhase.knownKeys),
        (plan.spending.flexible!, FlexibleSpending.knownKeys),
        (plan.pensions[0], PlanPension.knownKeys),
        (plan.income[0], PlanIncome.knownKeys),
        (plan.contributions[0], PlanContribution.knownKeys),
        (plan.portfolio, PlanPortfolio.knownKeys),
        (plan.portfolio.targetMixByAge[0], TargetMixStep.knownKeys),
        (plan.assumptions, PlanAssumptions.knownKeys),
        // Only a file edited by hand writes both the mean and the median.
        (try! JSONDecoder().decode(ReturnAssumption.self, from: Data(
            #"{ "real": "0", "medianReal": "0", "volatility": "0", "incomeYield": "0.02" }"#.utf8)),
         ReturnAssumption.knownKeys),
        (plan.simulation, PlanSimulation.knownKeys),
        (ImportProfile(id: "p", name: "P", file: ImportFileSettings(encoding: .utf8, delimiter: ";", headerRow: 1, excludeRows: ["Totale"]),
                       defaults: format, layout: .long, dateColumn: "Data", target: .balance,
                       constants: ImportConstants(account: "a"), columns: [ImportColumn(header: "A")],
                       matches: ImportMatches(accounts: ["A": "a"]), onConflict: .keep,
                       tradeTypes: ["Acquisto": .buy]), ImportProfile.knownKeys),
        (ImportFileSettings(encoding: .utf8, delimiter: ";", headerRow: 1, excludeRows: ["Totale"]), ImportFileSettings.knownKeys),
        (ImportColumn(header: "A", index: 1, target: .fx, field: .value, account: "a", instrument: "i", currency: .eur,
                      base: .eur, quote: .usd, format: format), ImportColumn.knownKeys),
        (ImportConstants(account: "a", instrument: "i", currency: .eur, base: .eur, quote: .usd, settlement: .external),
         ImportConstants.knownKeys),
        (ImportMatches(accounts: ["A": "a"], instruments: ["I": "i"]), ImportMatches.knownKeys),
        (format, ImportFormat.knownKeys),
        (format.date!, ImportDateFormat.knownKeys),
        (format.number!, ImportNumberFormat.knownKeys),
        (Baseline(created: "2026-01-05", kind: .yearly, label: "L", engine: "1", accounts: ["a"], headline: summary,
                  plan: ["id": "base"], start: BaselineStart(date: "2025-12-31", value: 1), years: []),
         Baseline.knownKeys),
        (BaselineStart(date: "2025-12-31", value: 1), BaselineStart.knownKeys),
        (BaselineYear(year: 2026, expected: 1, p10: 1, p25: 1, p50: 1, p75: 1, p90: 1, savings: 1), BaselineYear.knownKeys),
        (summary, HeadlineSummary.knownKeys),
        (HeadlineFile(headlines: []), HeadlineFile.knownKeys),
        (Headline(date: "2026-09-30", coastAge: 61, confidence: d("0.9"), earliestAge: 54, engine: "1",
                  planHash: "h", readiness: d("0.58"), successAtTarget: d("0.8")),
         Headline.knownKeys),
    ] }

    @Test func writtenKeysAreExactlyTheKnownKeys() throws {
        for (value, knownKeys) in Self.samples {
            let json = try JSONValue(encoding: value)
            let keys = Set(try #require(json.objectValue).keys)
            #expect(keys == knownKeys, "\(type(of: value)): writes \(keys.sorted()), knows \(knownKeys.sorted())")
        }
    }

    @Test func eventKeysCoverBothTimings() throws {
        let byAge = try JSONValue(encoding: PlanEvent(name: "a", timing: .age(1), amount: 1, probability: 1))
        let byYear = try JSONValue(encoding: PlanEvent(name: "a", timing: .year(2030), amount: 1))
        let keys = Set(byAge.objectValue!.keys).union(byYear.objectValue!.keys)
        #expect(keys == PlanEvent.knownKeys)
    }
}
