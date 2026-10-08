import Foundation
import Model
import Testing

struct JSONValueTests {
    @Test func decodesEveryKind() throws {
        let json = #"{"a":null,"b":true,"c":0.1,"d":"0.0173","e":[1,"x",false],"f":{"g":2025}}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(value["a"] == .null)
        #expect(value["b"] == .bool(true))
        #expect(value["c"] == .number(Decimal(sign: .plus, exponent: -1, significand: 1)))
        #expect(value["d"] == .string("0.0173"))
        #expect(value["e"] == [1, "x", false])
        #expect(value["f"]?["g"]?.intValue == 2025)
    }

    @Test func numbersRoundTripExactly() throws {
        for text in ["0.1", "1234.56", "0.4215", "-2", "123456789012345678901234567890.5"] {
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            #expect(value.decimalValue?.fileString == text)
            let reencoded = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
            #expect(reencoded == text)
        }
    }

    @Test func accessors() {
        let options: JSONValue = ["movedIn": 2025, "rate": "0.0173", "list": ["a"]]
        #expect(options["movedIn"]?.intValue == 2025)
        #expect(options["rate"]?.decimalValue == Decimal(fileString: "0.0173"))
        #expect(options["rate"]?.intValue == nil)
        #expect(options["list"]?[0]?.stringValue == "a")
        #expect(options["list"]?[1] == nil)
        #expect(options["missing"] == nil)
        #expect(JSONValue.string("8").intValue == 8)
    }

    @Test func convertsModelValues() throws {
        let position = Position(instrument: "vwce", quantity: Decimal(fileString: "412.5")!)
        let value = try JSONValue(encoding: position)
        #expect(value == ["instrument": "vwce", "quantity": "412.5"])
        #expect(try value.decode(as: Position.self) == position)
    }
}
