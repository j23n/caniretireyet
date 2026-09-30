import Foundation
@testable import RetireCLI
import Testing

struct FormattingTests {
    @Test func amounts() {
        #expect(Format.amount(dec("1234567.891")) == "1,234,567.89")
        #expect(Format.amount(dec("-310.2")) == "-310.20")
        #expect(Format.amount(0) == "0.00")
        #expect(Format.amount(dec("999.995")) == "1,000.00")
        #expect(Format.amount(dec("-0.001")) == "0.00")
        #expect(Format.signed(dec("5417.66")) == "+5,417.66")
        #expect(Format.signed(dec("-0.004")) == "0.00")
        #expect(Format.exact(dec("0.4215")) == "0.4215")
        #expect(Format.exact(146_250) == "146,250")
        #expect(Format.percent(dec("0.9384")) == "93.8%")
        #expect(Format.signedPercent(dec("0.0166")) == "+1.7%")
        #expect(Format.json(dec("41196.2837")) == "41196.28")
    }

    @Test func tablesAndCSV() {
        var table = TextTable([.left("Name"), .right("Value")])
        table.add(["Cash", "1.00"])
        table.add(["Brokerage", "12,345.00"])
        #expect(table.lines() == ["  Name           Value", "  Cash            1.00", "  Brokerage  12,345.00"])
        #expect(CSV.line(["a", "b,c", "say \"hi\""]) == #"a,"b,c","say ""hi""""#)
    }
}
