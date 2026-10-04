import Foundation
import Model

extension PlanDebugReport {
    /// A copy to give to other people (PLANNER.md, "Plan debugger"):
    ///
    /// - account, instrument, plan, pension and event names and IDs become
    ///   neutral labels ("Account 2 (ordinary, equity)", "Instrument 1 (ETF,
    ///   equity fund)", "Pension 1 (statutory)"), wherever they appear,
    ///   messages included;
    /// - the birth date is removed; ages and calendar years stay, since tax
    ///   rules depend on them;
    /// - money amounts are rounded as `options` says (3 significant figures
    ///   by default);
    /// - amounts, rates, years and tax options otherwise stay, so the
    ///   reasoning can still be followed.
    ///
    /// A name that is also a tax system's own term (an account named "TFR",
    /// like the `it.tfr` wrapper) is replaced where it names the account,
    /// and kept where the tax system uses the term. The header says what was
    /// done, and the diagnosis is recomputed from the rounded figures.
    public func anonymized(_ options: PlanDebugAnonymization = PlanDebugAnonymization()) -> PlanDebugReport {
        let anonymizer = PlanDebugAnonymizer(report: self, options: options)
        var report = mapped(anonymizer.mapper)
        report.header.anonymization = AnonymizationNote(rounding: options.rounding.rawValue, notes: anonymizer.notes)
        report.diagnosis = PlanDebugDiagnosis.findings(for: report)
        return report
    }
}

/// The labels and replacements behind ``PlanDebugReport/anonymized(_:)``.
struct PlanDebugAnonymizer {
    private(set) var mapper = DebugMapper()
    let notes: [String]

    init(report: PlanDebugReport, options: PlanDebugAnonymization) {
        var accountIDs: [String: String] = [:]
        var accountLabels: [String: String] = [:]
        for (index, account) in report.start.accounts.enumerated() {
            accountIDs[account.id] = "account-\(index + 1)"
            accountLabels[account.id] = "Account \(index + 1) (\(Self.describe(account)))"
        }
        var instrumentIDs: [String: String] = [:]
        var instrumentLabels: [String: String] = [:]
        for (index, instrument) in report.start.instruments.enumerated() {
            instrumentIDs[instrument.id] = "instrument-\(index + 1)"
            instrumentLabels[instrument.id] = "Instrument \(index + 1) (\(Self.describe(instrument)))"
        }
        var pensionLabels: [String: String] = [:]
        for (index, pension) in report.plan.pensions.enumerated() where pensionLabels[pension.name] == nil {
            pensionLabels[pension.name] = "Pension \(index + 1) (\(pension.kind ?? pension.scheme))"
        }
        var eventLabels: [String: String] = [:]
        for (index, event) in report.plan.events.enumerated() where eventLabels[event.name] == nil {
            eventLabels[event.name] = "Event \(index + 1) (\(event.kind))"
        }
        let planID = report.header.planID
        let planName = report.header.planName

        // Free text: every original name and ID, longest first, except the
        // tax systems' own terms.
        let vocabulary = Self.vocabulary(of: report)
        var entries: [Entry] = []
        func add(_ needle: String, _ replacement: String, isID: Bool = false) {
            let trimmed = needle.trimmingCharacters(in: .whitespaces)
            guard trimmed.count > 1, !vocabulary.contains(trimmed.lowercased()) else { return }
            entries.append(Entry(needle: trimmed, replacement: replacement, isID: isID))
        }
        for account in report.start.accounts {
            add(account.name, accountLabels[account.id]!)
            add(account.id, accountIDs[account.id]!, isID: true)
        }
        for instrument in report.start.instruments {
            add(instrument.name, instrumentLabels[instrument.id]!)
            add(instrument.id, instrumentIDs[instrument.id]!, isID: true)
        }
        for (name, label) in pensionLabels { add(name, label) }
        for (name, label) in eventLabels { add(name, label) }
        add(planName, "Plan")
        add(planID, "plan", isID: true)
        let finalTable = Self.table(entries)

        mapper.money = options.round
        mapper.accountID = { accountIDs[$0] ?? "account" }
        mapper.accountName = { id, _ in accountLabels[id] ?? "An account" }
        mapper.instrumentID = { instrumentIDs[$0] ?? "instrument" }
        mapper.instrumentName = { id, _ in instrumentLabels[id] ?? "An instrument" }
        mapper.planID = { _ in "plan" }
        mapper.planName = { _ in "Plan" }
        mapper.pensionName = { pensionLabels[$0] ?? Self.replace(in: $0, finalTable) }
        mapper.eventName = { eventLabels[$0] ?? Self.replace(in: $0, finalTable) }
        mapper.text = { Self.replace(in: $0, finalTable) }
        let accounts = Dictionary(report.start.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let general = entries
        mapper.accountText = { text, id in
            // The account's own name and ID, whatever else they mean.
            guard let account = accounts[id] else { return Self.replace(in: text, finalTable) }
            let forced = general + [
                Entry(needle: account.name, replacement: accountLabels[id]!, isID: false),
                Entry(needle: account.id, replacement: accountIDs[id]!, isID: true),
            ]
            return Self.replace(in: text, Self.table(forced))
        }
        mapper.birthDate = { _ in nil }

        let rounding = switch options.rounding {
        case .none: "Money amounts are exact."
        case .hundreds: "Money amounts are rounded to the nearest 100, so totals may not add up exactly."
        case .significantFigures: "Money amounts are rounded to 3 significant figures, so totals may not add up exactly."
        }
        notes = [
            "Account, instrument, plan, pension and event names and IDs are replaced by neutral labels.",
            "The birth date is removed; ages and calendar years stay, as tax rules depend on them.",
            "Notes, institutions and other free text from the library are left out.",
            rounding,
            "Rates, ages, years and tax options are kept, so the reasoning can be followed.",
        ]
    }

    /// "ordinary, equity": the account's wrapper (its last part) and its
    /// largest asset class, or its kind.
    static func describe(_ account: PlanDebugReport.Account) -> String {
        let wrapper = (account.wrapper ?? account.bucket).map { $0.split(separator: ".").last.map(String.init) ?? $0 }
        var parts = [wrapper ?? account.kind]
        let main = Dictionary(account.holdings.filter { $0.value > 0 }.map { ($0.assetClass, $0.value) },
                              uniquingKeysWith: +).max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        if let main, main != parts[0] { parts.append(main) }
        return parts.joined(separator: ", ")
    }

    /// "ETF, equity fund": the instrument's kind and its fund type, or its
    /// largest asset class.
    static func describe(_ instrument: PlanDebugReport.Instrument) -> String {
        let kind = ["etf", "etc"].contains(instrument.kind) ? instrument.kind.uppercased() : instrument.kind
        let main = instrument.fundType.map { "\($0) fund" }
            ?? instrument.assetClasses.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        guard let main, main != kind else { return kind }
        return "\(kind), \(main)"
    }

    /// The tax systems' and the planner's own terms in a report, lowercased:
    /// they say nothing about the person, and replacing them would garble
    /// the report.
    static func vocabulary(of report: PlanDebugReport) -> Set<String> {
        var words: [String] = AssetClass.knownValues.map(\.rawValue) + AccountKind.knownValues.map(\.rawValue)
            + EventKind.knownValues.map(\.rawValue) + PlanPensionKind.knownValues.map(\.rawValue)
            + FundType.knownValues.map(\.rawValue) + InstrumentKind.knownValues.map(\.rawValue)
        words += report.assumptions.classes.map(\.assetClass) + report.start.classShares.keys
        for bucket in report.start.buckets { words += [bucket.wrapper, bucket.name, bucket.category] }
        for account in report.start.accounts {
            words += [account.kind] + [account.wrapper, account.bucket].compactMap { $0 }
            words += account.holdings.flatMap { [$0.assetClass, $0.category] }
        }
        words += report.start.instruments.flatMap { [$0.kind] + [$0.fundType].compactMap { $0 } }
        for residence in report.plan.residence { words += [residence.system, residence.systemName] }
        for overlay in report.plan.overlays { words += [overlay.regime, overlay.name] }
        for work in report.plan.work { words += [work.kind, work.label] + [work.regime].compactMap { $0 } }
        for pension in report.plan.pensions {
            words += [pension.scheme, pension.schemeName, pension.taxedIn] + [pension.kind].compactMap { $0 }
            words += pension.offered.flatMap { [$0.route, $0.label] }
        }
        words += report.plan.events.map(\.kind)
        words += report.plan.contributions.map(\.wrapper)
        for year in report.schedule.years {
            words += (year.taxes + year.socialContributions).flatMap { [$0.id, $0.label] }
            words += year.credits.flatMap { [$0.id, $0.label] }
        }
        for path in report.paths {
            words += path.buckets.flatMap { [$0.wrapper, $0.name] } + path.classes
            for year in path.years {
                words += year.taxes.flatMap { [$0.id, $0.label] } + year.sales.map(\.category)
            }
        }
        return Set(words.map { $0.lowercased() })
    }

    // MARK: Whole-word replacement

    /// A name or ID and what replaces it.
    struct Entry {
        let needle: String
        let replacement: String
        let isID: Bool
    }

    /// The replacements in the order they're tried: longest first, a name
    /// before an ID of the same length (an account named "TFR" with the ID
    /// `tfr` reads as its label).
    static func table(_ entries: [Entry]) -> [(String, String)] {
        entries.enumerated().sorted { a, b in
            let x = (a.element.needle.count, a.element.isID ? 0 : 1, -a.offset)
            let y = (b.element.needle.count, b.element.isID ? 0 : 1, -b.offset)
            return x > y
        }.map { ($0.element.needle, $0.element.replacement) }
    }

    /// `text` with each needle replaced where it stands as a whole word,
    /// ignoring case: not inside a longer word or ID (letters, digits, `_`,
    /// `-`, and a `.` between two of them, so `it.tfr` is one word). The
    /// longest needle that matches at a position wins.
    static func replace(in text: String, _ table: [(String, String)]) -> String {
        guard !table.isEmpty, !text.isEmpty else { return text }
        let characters = Array(text)
        let lowered = characters.map { String($0).lowercased() }
        let needles = table.map { (Array($0.0).map { String($0).lowercased() }, $0.1) }
        var result = ""
        var index = 0
        scan: while index < characters.count {
            for (needle, replacement) in needles where matches(needle, at: index, in: lowered, characters) {
                result += replacement
                index += needle.count
                continue scan
            }
            result.append(characters[index])
            index += 1
        }
        return result
    }

    /// Whether `needle` occurs in `text` as a whole word, ignoring case.
    static func containsWord(_ needle: String, in text: String) -> Bool {
        let characters = Array(text)
        let lowered = characters.map { String($0).lowercased() }
        let pattern = Array(needle).map { String($0).lowercased() }
        guard !pattern.isEmpty else { return false }
        return characters.indices.contains { matches(pattern, at: $0, in: lowered, characters) }
    }

    private static func matches(_ needle: [String], at index: Int, in lowered: [String], _ characters: [Character])
        -> Bool {
        let end = index + needle.count
        guard end <= lowered.count else { return false }
        for offset in needle.indices where lowered[index + offset] != needle[offset] { return false }
        if isWord(characters[index]), index > 0 {
            if isWord(characters[index - 1]) { return false }
            if characters[index - 1] == ".", index > 1, isWord(characters[index - 2]) { return false }
        }
        if isWord(characters[end - 1]), end < characters.count {
            if isWord(characters[end]) { return false }
            if characters[end] == ".", end + 1 < characters.count, isWord(characters[end + 1]) { return false }
        }
        return true
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }
}
