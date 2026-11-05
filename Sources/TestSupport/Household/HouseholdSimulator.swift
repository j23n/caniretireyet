import Foundation
import Model

/// What a simulated household has, and which of the records that leave the
/// app to guess its person makes.
public struct HouseholdOptions: Hashable, Sendable {
    /// How many calendar years it runs, 1 to 3; `nil` takes it from the seed.
    public var years: Int?
    /// Whether the broker also holds a stock priced in dollars; `nil` takes it from the seed.
    public var dollarStock: Bool?
    /// Whether an inheritance arrives; `nil` takes it from the seed.
    public var inheritance: Bool?
    /// Whether a car is bought, and maybe sold; `nil` takes it from the seed.
    public var car: Bool?
    /// One month end, not the last, without a check-in.
    public var skippedCheckIn: Bool
    /// About a quarter of the pension's values typed without what was paid in.
    public var pensionWithoutSaved: Bool
    /// A second savings account opened during the run, holding money from
    /// outside and then a transfer from the current account.
    public var newAccount: Bool

    public init(years: Int? = nil, dollarStock: Bool? = nil, inheritance: Bool? = nil, car: Bool? = nil,
                skippedCheckIn: Bool = false, pensionWithoutSaved: Bool = false, newAccount: Bool = false) {
        self.years = years
        self.dollarStock = dollarStock
        self.inheritance = inheritance
        self.car = car
        self.skippedCheckIn = skippedCheckIn
        self.pensionWithoutSaved = pensionWithoutSaved
        self.newAccount = newAccount
    }
}

/// Plays out a made-up household's money day by day from a seed
/// (``HouseholdRandom``), the same household for a seed on every platform: pay
/// and bonuses, spending by debit and by card, refunds, the card's bill,
/// transfers to savings and to a broker, buys, sales and dividends, an
/// employer's pension contributions, a mortgage's principal and interest,
/// a yearly tax bill, and from the seed or ``HouseholdOptions``, a dollar
/// stock, an inheritance and a car bought and maybe sold.
public enum HouseholdSimulator {
    public static func household(seed: UInt64, options: HouseholdOptions = HouseholdOptions()) -> Household {
        var generator = Generator(seed: seed, options: options)
        return generator.run()
    }
}

private struct Generator {
    typealias A = HouseholdAccount
    typealias Kind = HouseholdEvent.Kind

    let seed: UInt64
    let options: HouseholdOptions
    var rng: HouseholdRandom
    let start: CalendarDate
    let end: CalendarDate
    let opening: HouseholdOpening
    let markets: HouseholdMarkets
    let hasStock: Bool
    var state: HouseholdState
    var events: [HouseholdEvent] = []
    /// Events planned for a day: purchases, refunds.
    var planned: [CalendarDate: [Kind]] = [:]

    // The household's habits.
    let mortgageRate: Int
    let mortgagePayment: Decimal
    let savingsRate: Int
    let dividendPerUnit: Decimal
    let carLossRate: Int
    var pay: Decimal
    var contribution: Decimal = 0
    var toSavings: Decimal = 0
    var toBroker: Decimal = 0
    var bonus: (month: YearMonth, amount: Decimal)?
    var taxBill: (date: CalendarDate, amount: Decimal)?
    var cardOwed: Decimal
    var buyDay = 5
    var sells = false

    // The one-off events.
    var inheritance: (date: CalendarDate, amount: Decimal)?
    var carBought: (date: CalendarDate, price: Decimal)?
    var carSold: CalendarDate?
    var online: (opened: CalendarDate, outside: Decimal, moved: CalendarDate, amount: Decimal)?

    init(seed: UInt64, options: HouseholdOptions) {
        self.seed = seed
        self.options = options
        var rng = HouseholdRandom(seed: seed)
        let firstYear = 2019 + rng.int(in: 0...3)
        // Every draw is made whatever the options, so an option changes only what it's about.
        let drawnYears = rng.int(in: 1...3)
        let drawnStock = rng.chance(50)
        let drawnInheritance = rng.chance(50)
        let drawnCar = rng.chance(50)
        let years = min(max(options.years ?? drawnYears, 1), 3)
        start = CalendarDate.lastDay(ofYear: firstYear - 1)
        end = CalendarDate.lastDay(ofYear: firstYear + years - 1)
        hasStock = options.dollarStock ?? drawnStock
        markets = HouseholdMarkets.random(start: start, days: start.days(to: end), using: &rng)

        let mortgage = -rng.amount(cents: 8_000_000...25_000_000).rounded(scale: 0)
        mortgageRate = rng.int(in: 150...450)
        mortgagePayment = (-mortgage * Decimal(mortgageRate + 300) / 120_000).rounded(scale: 0)
        savingsRate = rng.int(in: 50...300)
        dividendPerUnit = rng.amount(cents: 10...50)
        carLossRate = rng.int(in: 100...200)
        pay = rng.amount(cents: 220_000...450_000)
        cardOwed = rng.amount(cents: 20_000...150_000)

        var holdings: [InstrumentID: HouseholdOpening.Holding] = [:]
        let etfUnits = Decimal(rng.int(in: 10...300))
        holdings[A.etf] = HouseholdOpening.Holding(
            quantity: etfUnits,
            cost: (markets.value(of: etfUnits, A.etf, on: start) * Decimal(rng.int(in: 70...120)) / 100)
                .rounded(scale: 2))
        if hasStock {
            let units = Decimal(rng.int(in: 5...50))
            holdings[A.stock] = HouseholdOpening.Holding(
                quantity: units,
                cost: (markets.value(of: units, A.stock, on: start) * Decimal(rng.int(in: 70...120)) / 100)
                    .rounded(scale: 2))
        }
        var balances: [AccountID: Decimal] = [
            A.current: rng.amount(cents: 200_000...800_000),
            A.savings: rng.amount(cents: 500_000...4_000_000),
            A.card: -cardOwed,
            A.mortgage: mortgage,
            A.pension: rng.amount(cents: 500_000...6_000_000),
        ]
        let hasCar = options.car ?? drawnCar
        if hasCar { balances[A.car] = 0 }
        opening = HouseholdOpening(balances: balances, brokerCash: rng.amount(cents: 0...200_000),
                                   holdings: holdings)
        state = HouseholdState(opening)

        let months = years * 12
        let inheritanceDay = Self.randomDay(after: start, months: 0...(months - 1), using: &rng)
        let inheritanceAmount = rng.amount(cents: 500_000...4_000_000)
        if options.inheritance ?? drawnInheritance { inheritance = (inheritanceDay, inheritanceAmount) }
        let bought = Self.randomDay(after: start, months: 0...max(0, months / 2 - 1), using: &rng)
        let price = rng.amount(cents: 800_000...2_500_000).rounded(scale: 0)
        let earliest = bought.adding(days: 60)
        let sold = rng.chance(60) && earliest < end.adding(days: -2)
            ? earliest.adding(days: rng.int(in: 0...(earliest.days(to: end) - 2))) : nil
        if hasCar {
            carBought = (bought, price)
            carSold = sold
        }
        let onlineMonth = start.yearMonth.adding(months: rng.int(in: 3...max(3, months - 2)))
        let opened = CalendarDate(year: onlineMonth.year, month: onlineMonth.month, day: rng.int(in: 1...20))
            ?? onlineMonth.firstDay
        let moved = opened.adding(days: rng.int(in: 1...(opened.days(to: onlineMonth.lastDay))))
        let outside = rng.amount(cents: 100_000...2_000_000)
        let amount = rng.amount(cents: 50_000...500_000)
        if options.newAccount, onlineMonth.lastDay <= end { online = (opened, outside, moved, amount) }
        self.rng = rng
    }

    /// A day in one of the months `months` after the one after `date`'s
    /// (0 is the next month), from its first through its 28th.
    private static func randomDay(after date: CalendarDate, months: ClosedRange<Int>, using rng: inout HouseholdRandom)
        -> CalendarDate {
        let month = date.yearMonth.adding(months: 1 + rng.int(in: months))
        return CalendarDate(year: month.year, month: month.month, day: rng.int(in: 1...28)) ?? month.firstDay
    }

    mutating func emit(_ kind: Kind, on date: CalendarDate) {
        let event = HouseholdEvent(id: events.count, date: date, kind: kind)
        _ = state.apply(event)
        events.append(event)
    }

    mutating func run() -> Household {
        var date = start.adding(days: 1)
        while date <= end {
            if date.day == 1 { startMonth(date) }
            day(date)
            date = date.adding(days: 1)
        }
        // What the person records comes from a stream of its own, so it leaves the events as they are.
        var records = HouseholdRecords()
        var recording = HouseholdRandom(seed: ~seed)
        let monthEnds = Household.monthEnds(after: start, through: end)
        let skipped = monthEnds[recording.int(in: 0...max(0, monthEnds.count - 2))]
        if options.skippedCheckIn, monthEnds.count > 1 { records.skippedCheckIns = [skipped] }
        var withoutSaved = Set(monthEnds.filter { _ in recording.chance(25) })
        if withoutSaved.isEmpty { withoutSaved = [recording.pick(monthEnds)] }
        if options.pensionWithoutSaved { records.pensionWithoutSaved = withoutSaved }
        return Household(seed: seed, start: start, end: end, opening: opening, events: events, markets: markets,
                         hasCar: opening.balances[A.car] != nil, hasStock: hasStock,
                         onlineOpened: online?.opened, records: records)
    }

    /// The month's habits and its planned purchases.
    mutating func startMonth(_ first: CalendarDate) {
        let month = first.yearMonth
        if month.month == 1 || events.isEmpty {
            if !events.isEmpty { pay = (pay * Decimal(100 + rng.int(in: 0...4)) / 100).rounded(scale: 2) }
            contribution = (pay * Decimal(rng.int(in: 5...10)) / 100).rounded(scale: 2)
            toSavings = rng.amount(cents: 20_000...100_000).rounded(scale: 0)
            toBroker = rng.amount(cents: 10_000...80_000).rounded(scale: 0)
            bonus = rng.chance(70)
                ? (YearMonth(year: month.year, month: rng.int(in: 3...12)) ?? month,
                   (pay * Decimal(rng.int(in: 50...150)) / 100).rounded(scale: 2))
                : nil
            let taxMonth = rng.int(in: 4...7)
            taxBill = (CalendarDate(year: month.year, month: taxMonth, day: rng.int(in: 1...28)) ?? first,
                       rng.amount(cents: 20_000...300_000))
        }
        buyDay = rng.int(in: 5...9)
        sells = rng.chance(8)
        let lastDay = month.lastDay.day
        for _ in 0..<rng.int(in: 4...10) {
            let date = CalendarDate(year: month.year, month: month.month, day: rng.int(in: 1...lastDay)) ?? first
            planned[date, default: []].append(.spend(spending(), merchant: rng.pick(Self.shops)))
        }
        for _ in 0..<rng.int(in: 8...25) {
            let date = CalendarDate(year: month.year, month: month.month, day: rng.int(in: 1...lastDay)) ?? first
            planned[date, default: []].append(.cardSpend(rng.amount(cents: 300...15_000),
                                                         merchant: rng.pick(Self.shops)))
        }
    }

    static let shops = ["Corner Grocer", "City Power", "Rail Pass", "Book Nook", "Hardware Hub", "Cafe Lumen",
                        "Pharma Plus", "Garden Centre", "Sport Depot", "Music Box"]

    /// A debit purchase: mostly small, sometimes a bill.
    mutating func spending() -> Decimal {
        switch rng.int(in: 0...99) {
        case ..<70: rng.amount(cents: 500...8_000)
        case ..<95: rng.amount(cents: 8_000...30_000)
        default: rng.amount(cents: 30_000...90_000)
        }
    }

    mutating func day(_ date: CalendarDate) {
        let month = date.yearMonth
        if date.day == 1, state[A.mortgage] < 0 {
            let interest = (-state[A.mortgage] * Decimal(mortgageRate) / 120_000).rounded(scale: 2)
            let principal = min(mortgagePayment - interest, -state[A.mortgage])
            emit(.mortgagePayment(principal: principal, interest: interest), on: date)
        }
        if date.day == 3, state[A.current] - toBroker >= 1000 {
            emit(.deposit(toBroker), on: date)
        }
        if date.day == buyDay { buy(on: date) }
        if date.day == 10, cardOwed > 0 {
            emit(.cardBill(cardOwed), on: date)
        }
        if date.day == 15, month.month % 3 == 0, let units = state.holdings[A.etf], units > 0 {
            emit(.dividend(A.etf, (units * dividendPerUnit).rounded(scale: 2)), on: date)
        }
        if date.day == 20, sells { sell(on: date) }
        if let taxBill, taxBill.date == date {
            emit(.taxBill(taxBill.amount), on: date)
        }
        if let inheritance {
            if inheritance.date == date { emit(.inheritance(inheritance.amount), on: date) }
            if inheritance.date.adding(days: 5) == date {
                emit(.toSavings((inheritance.amount / 2).rounded(scale: 0)), on: date)
            }
        }
        if let carBought {
            if carBought.date.adding(days: -2) == date {
                let short = carBought.price + 1500 - state[A.current]
                if short > 0, state[A.savings] >= short { emit(.fromSavings(short.rounded(scale: 0)), on: date) }
            }
            if carBought.date == date { emit(.buyCar(carBought.price), on: date) }
        }
        if carSold == date, state[A.car] > 0 {
            emit(.sellCar((state[A.car] * Decimal(rng.int(in: 85...105)) / 100).rounded(scale: 0)), on: date)
        }
        if let online {
            if online.opened == date { emit(.openOnline(online.outside), on: date) }
            if online.moved == date { emit(.toOnline(online.amount), on: date) }
        }
        for kind in planned.removeValue(forKey: date) ?? [] {
            emit(kind, on: date)
            planRefund(of: kind, on: date)
        }
        if date.day == 25, state[A.current] < 500 {
            let needed = (1500 - state[A.current]).rounded(scale: 0)
            if state[A.savings] >= needed { emit(.fromSavings(needed), on: date) }
        }
        if date.day == 27 {
            emit(.pay(pay), on: date)
            if let bonus, bonus.month == month { emit(.bonus(bonus.amount), on: date) }
            emit(.pensionContribution(contribution), on: date)
        }
        if date.day == 28, state[A.current] - toSavings >= 1500 {
            emit(.toSavings(toSavings), on: date)
        }
        if date.isEndOfMonth { endMonth(date) }
    }

    /// Now and then a purchase is refunded, in part, a few days later.
    mutating func planRefund(of kind: Kind, on date: CalendarDate) {
        let refundDate = date.adding(days: rng.int(in: 1...10))
        guard refundDate <= end else { return }
        switch kind {
        case .spend(let amount, let merchant) where rng.chance(4):
            planned[refundDate, default: []].append(
                .refund((amount * Decimal(rng.int(in: 10...100)) / 100).rounded(scale: 2), merchant: merchant))
        case .cardSpend(let amount, let merchant) where rng.chance(3):
            planned[refundDate, default: []].append(
                .cardRefund((amount * Decimal(rng.int(in: 10...100)) / 100).rounded(scale: 2), merchant: merchant))
        default:
            break
        }
    }

    mutating func buy(on date: CalendarDate) {
        let instrument = hasStock && rng.chance(30) ? A.stock : A.etf
        let fees = rng.pick([Decimal(0), d("1.5"), d("2.95"), 5])
        let unit = markets.value(of: 1, instrument, on: date)
        let units = ((state.brokerCash - fees) / unit).rounded(scale: 0)
        let quantity = units * unit + fees > state.brokerCash ? units - 1 : units
        guard quantity >= 1 else { return }
        let amount = markets.value(of: quantity, instrument, on: date).rounded(scale: 2) + fees
        emit(.buy(instrument, quantity: quantity, price: markets.price(of: instrument, on: date), amount: amount,
                  fees: fees), on: date)
    }

    mutating func sell(on date: CalendarDate) {
        let held = state.holdings.filter { $0.value > 0 }.keys.sorted()
        guard !held.isEmpty else { return }
        let instrument = rng.pick(held)
        let units = state.holdings[instrument] ?? 0
        let quantity = max(1, (units * Decimal(rng.int(in: 20...60)) / 100).rounded(scale: 0))
        let fees = rng.pick([Decimal(0), d("1.5"), d("2.95"), 5])
        let amount = markets.value(of: min(quantity, units), instrument, on: date).rounded(scale: 2) - fees
        emit(.sell(instrument, quantity: min(quantity, units), price: markets.price(of: instrument, on: date),
                   amount: amount, fees: fees), on: date)
    }

    mutating func endMonth(_ date: CalendarDate) {
        let interest = (state[A.savings] * Decimal(savingsRate) / 120_000).rounded(scale: 2)
        if interest > 0 { emit(.interest(interest), on: date) }
        if let online, online.opened.yearMonth < date.yearMonth {
            let interest = (state[A.online] * Decimal(savingsRate) / 120_000).rounded(scale: 2)
            if interest > 0 { emit(.onlineInterest(interest), on: date) }
        }
        let fundReturn = (state[A.pension] * Decimal(40 + rng.bell() / 5) / 10000).rounded(scale: 2)
        if fundReturn != 0 { emit(.fundReturn(fundReturn), on: date) }
        if state[A.car] > 0, let carBought, carBought.date <= date {
            emit(.carLoss((state[A.car] * Decimal(carLossRate) / 10000).rounded(scale: 2)), on: date)
        }
        cardOwed = max(-state[A.card], 0)
    }
}

extension Household {
    /// Every month end after `start` through `end`.
    static func monthEnds(after start: CalendarDate, through end: CalendarDate) -> [CalendarDate] {
        var dates: [CalendarDate] = []
        var month = start.yearMonth.next
        while month.lastDay <= end {
            dates.append(month.lastDay)
            month = month.next
        }
        return dates
    }
}
