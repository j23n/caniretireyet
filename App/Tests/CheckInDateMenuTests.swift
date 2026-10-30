import Foundation
import Model
import Testing
import Tracker
@testable import CanIRetireYet

/// The check-in's date menu (UI.md, "Date"), on a made-up current account
/// checked in at the end of July, August and September, with August's
/// lines off by 34,95.
struct CheckInDateMenuTests {
    static let locale = Locale(identifier: "en_US")

    static func library() -> Library {
        var library = Library(accounts: [
            Account(id: "conto", name: "Conto", kind: .cash, currency: .eur, opened: "2020-01-01"),
        ])
        library.upsert(Valuation(account: "conto", date: "2026-07-31", balance: 1000))
        library.upsert(Valuation(account: "conto", date: "2026-08-31", balance: d("964.95")))
        library.upsert(Valuation(account: "conto", date: "2026-09-30", balance: 900))
        library.upsert(BankLine(account: "conto", date: "2026-08-10", id: "shop", amount: -70,
                                statementClass: .spending, confirmed: true))
        library.upsert(BankLine(account: "conto", date: "2026-09-10", id: "shop", amount: d("-64.95"),
                                statementClass: .spending, confirmed: true))
        return library
    }

    @Test func itOffersTheSuggestedDateTodayAndSavedCheckIns() {
        let options = CheckInDateMenu.options(suggested: "2026-10-31", today: "2026-10-30", library: Self.library())
        #expect(options.map(\.date) == ["2026-10-31", "2026-10-30", "2026-09-30", "2026-08-31", "2026-07-31"])
        #expect(options[0].kind == .suggested)
        #expect(options[1].kind == .today)
        #expect(options[2].isSaved && !options[2].isOff)
        #expect(options[3].isOff)
        #expect(CheckInDateMenu.hint(options[0], locale: Self.locale) == "End of October, suggested")
        #expect(CheckInDateMenu.hint(options[2], locale: Self.locale) == "September check-in, saved: edit it")
        #expect(CheckInDateMenu.hint(options[3], locale: Self.locale).parts.count == 2)
    }

    @Test func aDateIsNewEditedOrBetweenTwo() {
        let library = Self.library()
        #expect(CheckInDateMenu.kind(of: "2026-10-31", in: library) == .new)
        #expect(CheckInDateMenu.kind(of: "2026-08-31", in: library) == .editing)
        #expect(CheckInDateMenu.kind(of: "2026-08-15", in: library) == .between("2026-07-31", "2026-08-31"))
        #expect(CheckInDateMenu.banner(for: .new, on: "2026-10-31", latest: "2026-09-30") == nil)
        let editing = CheckInDateMenu.banner(for: .editing, on: "2026-08-31", latest: "2026-09-30",
                                             locale: Self.locale)
        #expect(editing?.title == "Editing August's check-in")
        #expect(editing?.message.contains("only recorded at your latest check-in") == true)
    }

    @Test func aDateBeforeTheFirstHasABannerToo() {
        let library = Self.library()
        let kind = CheckInDateMenu.kind(of: "2025-12-31", in: library)
        #expect(kind == .beforeFirst("2026-07-31"))
        let banner = CheckInDateMenu.banner(for: kind, on: "2025-12-31", latest: "2026-09-30", locale: Self.locale)
        #expect(banner?.title == "A check-in before your first")
        #expect(banner?.message.contains("only recorded at your latest check-in") == true)
    }

    /// The check-in saves values on its date as it goes, which doesn't make
    /// a new check-in an edited one.
    @MainActor
    @Test func aNewCheckInStaysNewOnceAValueIsSaved() throws {
        let model = AppModel.preview(Self.library(), defaults: "check-in-date-kind-tests")
        model.checkIn.begin(on: "2026-10-31")
        #expect(model.checkIn.dateKind == .new)
        try model.library.update {
            $0.upsert(Valuation(account: "conto", date: "2026-10-31", balance: 950))
        }
        #expect(model.checkIn.dateKind == .new)
        model.checkIn.cancel()
        #expect(model.checkIn.dateKind == nil)
    }
}
