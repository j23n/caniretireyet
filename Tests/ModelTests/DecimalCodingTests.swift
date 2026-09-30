import Foundation
import Model
import Testing

/// A minimal type that codes one decimal with the model's helpers.
private struct Amount: Codable, Equatable {
    var value: Decimal
    var optional: Decimal?

    enum CodingKeys: String, CodingKey { case value, optional }

    init(value: Decimal, optional: Decimal? = nil) {
        self.value = value
        self.optional = optional
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        value = try c.decodeDecimal(forKey: .value)
        optional = try c.decodeDecimalIfPresent(forKey: .optional)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeDecimal(value, forKey: .value)
        try c.encodeDecimalIfPresent(optional, forKey: .optional)
    }
}

private func decode(_ json: String) throws -> Amount {
    try JSONDecoder().decode(Amount.self, from: Data(json.utf8))
}

private func encode(_ amount: Amount) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return String(decoding: try encoder.encode(amount), as: UTF8.self)
}

struct DecimalCodingTests {
    /// Each case: the text, and the exact value as significand × 10^exponent,
    /// built without any floating point.
    static let exactCases: [(String, Decimal)] = [
        ("0.1", Decimal(sign: .plus, exponent: -1, significand: 1)),
        ("1234.56", Decimal(sign: .plus, exponent: -2, significand: 123_456)),
        ("0.4215", Decimal(sign: .plus, exponent: -4, significand: 4215)),
        ("-310.2", Decimal(sign: .minus, exponent: -1, significand: 3102)),
    ]

    @Test(arguments: exactCases)
    func roundTripsExactlyFromString(text: String, exact: Decimal) throws {
        let amount = try decode(#"{"value":"\#(text)"}"#)
        #expect(amount.value == exact)
        #expect(amount.value.fileString == text)
        #expect(try encode(amount) == #"{"value":"\#(text)"}"#)
        #expect(try decode(try encode(amount)) == amount)
    }

    @Test(arguments: exactCases)
    func roundTripsExactlyFromNumber(text: String, exact: Decimal) throws {
        let amount = try decode(#"{"value":\#(text)}"#)
        #expect(amount.value == exact)
        // Written back as a string.
        #expect(try encode(amount) == #"{"value":"\#(text)"}"#)
    }

    @Test func numbersBeyondDoublePrecisionStayExact() throws {
        let digits = "123456789012345678901234567890.123"
        #expect(try decode(#"{"value":\#(digits)}"#).value.fileString == digits)
        #expect(try decode(#"{"value":"\#(digits)"}"#).value.fileString == digits)
    }

    @Test func trailingZerosAreNotKept() throws {
        let amount = try decode(#"{"value":"1500.00"}"#)
        #expect(amount.value == 1500)
        #expect(try encode(amount) == #"{"value":"1500"}"#)
    }

    @Test(arguments: ["", "abc", "12abc", "1,5", "1.234,56", "+1", " 1", "1 ", "1.", ".5", "1e", "€ 12", "NaN"])
    func rejectsMalformedStrings(text: String) {
        #expect(Decimal(fileString: text) == nil)
        #expect(throws: DecodingError.self) { try decode(#"{"value":"\#(text)"}"#) }
    }

    @Test func acceptsExponents() {
        #expect(Decimal(fileString: "1e3") == 1000)
        #expect(Decimal(fileString: "25E-2") == Decimal(sign: .plus, exponent: -2, significand: 25))
    }

    @Test func optionalDecimals() throws {
        #expect(try decode(#"{"value":"1"}"#).optional == nil)
        #expect(try decode(#"{"value":"1","optional":null}"#).optional == nil)
        #expect(try decode(#"{"value":"1","optional":"2.5"}"#).optional == Decimal(fileString: "2.5"))
        #expect(try encode(Amount(value: 1)) == #"{"value":"1"}"#)
    }

    @Test func missingRequiredDecimalThrows() {
        #expect(throws: DecodingError.self) { try decode(#"{}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"value":true}"#) }
    }
}
