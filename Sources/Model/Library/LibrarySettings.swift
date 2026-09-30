/// `library.json`: the library's settings and schema version.
///
/// Settings that belong to one device (reminders, UI state) are stored on
/// that device, not here.
public struct LibrarySettings: Codable, Hashable, Sendable, KnownKeysProviding {
    /// The schema version this app writes. An app that finds a newer version
    /// opens the library read-only.
    public static let currentSchemaVersion = 1

    /// The library's schema version. Adding optional fields doesn't change it.
    public var schemaVersion: Int
    /// The currency net worth is reported in.
    public var baseCurrency: CurrencyCode
    /// The person the library belongs to.
    public var person: Person?
    /// The country of tax residence today. Plans set residence over time.
    public var taxResidence: CountryCode?
    /// The plan shown on the Overview, re-run at each check-in and saved as a
    /// baseline automatically at the first check-in of each year.
    public var mainPlan: PlanID?

    public init(
        schemaVersion: Int = LibrarySettings.currentSchemaVersion,
        baseCurrency: CurrencyCode = .eur,
        person: Person? = nil,
        taxResidence: CountryCode? = nil,
        mainPlan: PlanID? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.baseCurrency = baseCurrency
        self.person = person
        self.taxResidence = taxResidence
        self.mainPlan = mainPlan
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, baseCurrency, person, taxResidence, mainPlan
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

/// The person a library belongs to. Plans use the birth date for ages.
public struct Person: Codable, Hashable, Sendable, KnownKeysProviding {
    public var name: String?
    public var birthDate: CalendarDate?

    public init(name: String? = nil, birthDate: CalendarDate? = nil) {
        self.name = name
        self.birthDate = birthDate
    }

    /// Age in whole years on `date`, if the birth date is known.
    public func age(on date: CalendarDate) -> Int? {
        birthDate?.wholeYears(to: date)
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, birthDate
    }

    public static var knownKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}
