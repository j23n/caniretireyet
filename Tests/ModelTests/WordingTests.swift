import Model
import Testing

struct WordingTests {
    @Test func counts() {
        #expect(Wording.count(0, "account") == "0 accounts")
        #expect(Wording.count(1, "account") == "1 account")
        #expect(Wording.count(12, "price") == "12 prices")
        #expect(Wording.count(1, "row skipped", plural: "rows skipped") == "1 row skipped")
        #expect(Wording.count(3, "row skipped", plural: "rows skipped") == "3 rows skipped")
    }

    @Test func lists() {
        #expect(Wording.list([]) == "")
        #expect(Wording.list(["Fineco"]) == "Fineco")
        #expect(Wording.list(["Fineco", "Directa"]) == "Fineco and Directa")
        #expect(Wording.list(["Fineco", "Directa", "TFR"]) == "Fineco, Directa and TFR")
        #expect(Wording.list(["a", "b", "c"], or: true) == "a, b or c")
        #expect(Wording.list(["Fineco", "Fineco"]) == "Fineco and Fineco")
    }

    @Test func capitalizedFirst() {
        #expect("in 9 of 10 futures".capitalizedFirst == "In 9 of 10 futures")
        #expect("2 years later".capitalizedFirst == "2 years later")
        #expect("".capitalizedFirst == "")
    }
}
