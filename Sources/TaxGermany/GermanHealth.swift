import TaxKit

/// The health insurance of the part of a year not covered by an employee's
/// statutory insurance.
enum HealthStatus: String, Hashable, Sendable {
    /// Voluntary GKV: contributions on all income, capital included, between
    /// the minimum base and the ceiling.
    case voluntary
    /// The pensioners' compulsory insurance (KVdR): contributions on pensions,
    /// occupational pensions and self-employment income only.
    case kvdr
    /// Private health insurance: the premium.
    case pkv
}

/// One kind of income health and care contributions are charged on, in the
/// order the law fills the ceiling with them (statutory pensions first, then
/// occupational pensions, self-employment income, the rest).
struct HealthItem: Hashable, Sendable {
    enum Kind: Int, Hashable, Sendable, Comparable {
        case statutoryPension = 1, occupationalPension, selfEmployment, other, capital

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var kind: Kind
    /// The base for health (after any allowance).
    var healthBase: Double
    /// The base for care.
    var careBase: Double
    /// The member's health rate on it.
    var rate: Double
    /// Whether contributions on it are deductible (not when the income is exempt in Germany).
    var deductible: Bool = true
}

/// Health and care contributions on a set of items.
struct HealthCharge: Hashable, Sendable {
    var health = 0.0
    var care = 0.0
    var deductibleHealth = 0.0
    var deductibleCare = 0.0

    static func + (lhs: HealthCharge, rhs: HealthCharge) -> HealthCharge {
        HealthCharge(health: lhs.health + rhs.health, care: lhs.care + rhs.care,
                     deductibleHealth: lhs.deductibleHealth + rhs.deductibleHealth,
                     deductibleCare: lhs.deductibleCare + rhs.deductibleCare)
    }

    static func - (lhs: HealthCharge, rhs: HealthCharge) -> HealthCharge {
        HealthCharge(health: lhs.health - rhs.health, care: lhs.care - rhs.care,
                     deductibleHealth: lhs.deductibleHealth - rhs.deductibleHealth,
                     deductibleCare: lhs.deductibleCare - rhs.deductibleCare)
    }

    /// Charges `items` up to `ceiling` in the law's order; below `minimum`,
    /// the difference at `minimumRate` (voluntary members).
    static func charge(_ items: [HealthItem], minimum: Double, ceiling: Double, minimumRate: Double,
                       careRate: Double) -> HealthCharge {
        var result = HealthCharge()
        var healthRoom = max(0, ceiling)
        var careRoom = max(0, ceiling)
        for item in items.sorted(by: { $0.kind < $1.kind }) {
            let health = min(max(0, item.healthBase), healthRoom)
            healthRoom -= health
            result.health += health * item.rate
            if item.deductible { result.deductibleHealth += health * item.rate }
            let care = min(max(0, item.careBase), careRoom)
            careRoom -= care
            result.care += care * careRate
            if item.deductible { result.deductibleCare += care * careRate }
        }
        let healthBase = max(0, ceiling) - healthRoom
        if healthBase < minimum {
            result.health += (minimum - healthBase) * minimumRate
            result.deductibleHealth += (minimum - healthBase) * minimumRate
        }
        let careBase = max(0, ceiling) - careRoom
        if careBase < minimum {
            result.care += (minimum - careBase) * careRate
            result.deductibleCare += (minimum - careBase) * careRate
        }
        return result
    }
}

/// The rates one person pays.
struct HealthRates: Hashable, Sendable {
    /// The general rate plus the Zusatzbeitrag.
    var general: Double
    /// The reduced rate (no sick pay) plus the Zusatzbeitrag.
    var reduced: Double
    /// An employee's share: half of the general rate and of the Zusatzbeitrag.
    var employee: Double
    /// An employee's share without sick pay (a full pension drawn).
    var employeeReduced: Double
    /// A statutory pension's: half the general rate and half the Zusatzbeitrag.
    var statutoryPension: Double
    /// A foreign statutory pension's.
    var foreignPension: Double
    /// Care paid in full by the member (self-employed, pensioners).
    var careFull: Double
    /// An employee's share of care.
    var careEmployee: Double

    init(_ p: GermanParameters, zusatzbeitrag: Double, person: GermanPerson, year: Int, state: String?) {
        let h = p.health
        general = h.generalRate + zusatzbeitrag
        reduced = h.reducedRate + zusatzbeitrag
        employee = (h.generalRate + zusatzbeitrag) * h.employeeShare
        employeeReduced = (h.reducedRate + zusatzbeitrag) * h.employeeShare
        statutoryPension = general * p.kvdr.statutoryPensionRateShare
        foreignPension = general * p.kvdr.foreignPensionRateShare
        let c = p.care
        let surcharge = person.childCount == 0 && person.age(in: year) >= c.childlessFromAge ? c.childlessSurcharge : 0
        let young = person.children(under: c.discountChildUnderAge, in: year)
        let discount = young >= c.discountFromChild
            ? c.discountPerChild * Double(min(young, c.discountToChild) - c.discountFromChild + 1) : 0
        careFull = max(0, c.rate + surcharge - discount)
        let saxony = state.map { $0.uppercased() == c.saxonyState } ?? false
        careEmployee = max(0, c.rate * c.employeeShare + surcharge + (saxony ? c.saxonyEmployeeExtra : 0) - discount)
    }
}

/// The facts about the person the German rules use.
struct GermanPerson: Hashable, Sendable {
    var birthYear: Int
    /// 1...12, when the birth date is known.
    var birthMonth: Int?
    var birthDay: Int?
    var childBirthYears: [Int]
    /// The number of children: the list's length, or the option `children` if larger.
    var childCount: Int

    func age(in year: Int) -> Int { year - birthYear }

    /// Children younger than `age` (born by `year`) in `year`.
    func children(under age: Int, in year: Int) -> Int {
        childBirthYears.filter { $0 <= year && year - $0 < age }.count
    }

    /// The months of `year` after the month an age of `months` is reached:
    /// from the month after it (from that month for someone born on the
    /// 1st, who reaches it the day before). Without a birth date, the age is
    /// taken as reached in December.
    func monthsAfterReaching(_ months: Int, in year: Int) -> Int {
        let birth = birthYear * 12 + (birthMonth ?? 12) - 1
        var first = birth + months + 1
        if birthDay == 1 { first -= 1 }
        return min(12, max(0, year * 12 + 12 - first))
    }
}

extension GermanYearCalculator {
    /// The KVdR's 9/10 test at a first pension in `claimYear`: in the second
    /// half of the working life (from `workStartYear` to the claim), at
    /// least 9/10 in statutory health insurance. Years in the residence
    /// timeline count when spent in `de` with GKV or in another EU/EEA
    /// country or Switzerland; years before it count by
    /// `insuredShareBeforePlan`; each child adds 3 years.
    func kvdrTest(claimYear: Int) -> (passes: Bool, insured: Double, required: Double) {
        let start = Double(options.int("workStartYear") ?? person.birthYear + p.kvdr.defaultWorkStartAge)
        let end = Double(claimYear)
        guard end > start else { return (true, 0, 0) }
        let middle = (start + end) / 2
        // Someone in PKV now is taken to have been in PKV before the plan too,
        // unless the option says otherwise.
        let privateNow = options.string("healthInsurance") == "pkv"
        let shareBefore = min(1, max(0, year.systemOptions.double("insuredShareBeforePlan") ?? (privateNow ? 0 : 1)))
        let timelineStart = year.residence.map(\.from).min()
        var insured = 0.0
        var cursor = middle
        while cursor < end - 1e-9 {
            let calendarYear = Int(cursor.rounded(.down))
            let next = min(end, Double(calendarYear + 1))
            let weight = next - cursor
            if let timelineStart, calendarYear >= timelineStart,
               let entry = year.residence.last(where: { $0.from <= calendarYear }) {
                insured += weight * insuredShare(of: entry)
            } else {
                insured += weight * shareBefore
            }
            cursor = next
        }
        let length = end - middle
        insured = min(length, insured + p.kvdr.yearsPerChild * Double(person.childCount))
        let required = p.kvdr.qualifyingShare * length
        return (insured >= required - 1e-9, insured, required)
    }

    /// How much a year under `entry` counts toward the KVdR: in `de`, unless
    /// in PKV; in an EU/EEA country or Switzerland (their system IDs are
    /// their country codes); not elsewhere, nor under `generic`.
    private func insuredShare(of entry: TaxPlan.Residence) -> Double {
        if entry.system == system.id {
            return entry.options.string("healthInsurance") == "pkv" ? 0 : 1
        }
        return p.kvdr.countries.contains(entry.system.uppercased()) ? 1 : 0
    }
}
