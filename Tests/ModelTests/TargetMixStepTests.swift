import Foundation
import Model
import Testing

/// A plan's target mix that changes with age (`portfolio.targetMixByAge`):
/// how it's written and read, which step is in force at an age, and
/// folding the steps already passed into `targetMix`. All made up.
struct TargetMixStepTests {
    private static func d(_ string: String) -> Decimal { Decimal(fileString: string)! }
    private func d(_ string: String) -> Decimal { Self.d(string) }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static let glidePath = PlanPortfolio(
        targetMix: [.equity: d("0.8"), .bonds: d("0.2")],
        targetMixByAge: [
            TargetMixStep(fromAge: .retirement, mix: [.equity: d("0.6"), .bonds: d("0.4")]),
            TargetMixStep(fromAge: .age(75), mix: [.equity: d("0.4"), .bonds: d("0.6")]),
        ])

    @Test func stepsRoundTripAfterTheTargetMix() throws {
        let text = #"""
        { "targetMix": { "bonds": "0.2", "equity": "0.8" },
          "targetMixByAge": [
            { "fromAge": "retirement", "mix": { "bonds": "0.4", "equity": "0.6" } },
            { "fromAge": 75, "mix": { "bonds": "0.6", "equity": "0.4" } } ] }
        """#
        let portfolio = try decode(PlanPortfolio.self, text)
        #expect(portfolio == Self.glidePath)
        #expect(try decode(JSONValue.self, try json(portfolio)) == decode(JSONValue.self, text))
        #expect(portfolio.choosesTargetMix && !portfolio.isEmpty)
        // An age written as a string reads too, and is written as a number.
        let step = try decode(TargetMixStep.self, #"{ "fromAge": "60", "mix": { "cash": "1" } }"#)
        #expect(step.fromAge == .age(60))
        #expect(try json(step) == #"{"fromAge":60,"mix":{"cash":"1"}}"#)
        #expect(throws: DecodingError.self) {
            try decode(TargetMixStep.self, #"{ "fromAge": "pension", "mix": { "cash": "1" } }"#)
        }
    }

    @Test func noStepsWriteNothing() throws {
        #expect(try json(PlanPortfolio(targetMix: [.equity: 1])) == #"{"targetMix":{"equity":"1"}}"#)
        #expect(PlanPortfolio().targetMixByAge.isEmpty && !PlanPortfolio().choosesTargetMix)
        #expect(try decode(PlanPortfolio.self, "{}").targetMixByAge.isEmpty)
        // Steps alone choose a mix from their age; the accounts keep theirs until then.
        #expect(PlanPortfolio(targetMixByAge: [TargetMixStep(fromAge: .age(60), mix: [.bonds: 1])]).choosesTargetMix)
    }

    /// The step in force is the last one in the list that has started: a
    /// `retirement` step at the retirement age, never without one.
    @Test func theLastStepThatHasStartedIsInForce() {
        let portfolio = Self.glidePath
        #expect(portfolio.targetMix(atAge: 50, retiringAt: 55) == portfolio.targetMix)
        #expect(portfolio.targetMixStep(atAge: 55, retiringAt: 55) == 0)
        #expect(portfolio.targetMixStep(atAge: 74, retiringAt: 55) == 0)
        #expect(portfolio.targetMix(atAge: 75, retiringAt: 55) == [.equity: d("0.4"), .bonds: d("0.6")])
        #expect(portfolio.targetMixStep(atAge: 90, retiringAt: nil) == 1)
        #expect(portfolio.targetMixStep(atAge: 60, retiringAt: nil) == nil)
        // Retiring at 76, the step from 75 has started already, and stays.
        #expect(portfolio.targetMixStep(atAge: 75, retiringAt: 76) == 1)
        #expect(portfolio.targetMixStep(atAge: 80, retiringAt: 76) == 1)
        #expect(MixStepStart.retirement.startAge(retiringAt: 58) == 58)
        #expect(MixStepStart.age(70).startAge(retiringAt: 58) == 70)
        #expect(MixStepStart.retirement.age == nil && MixStepStart.age(70).age == 70)
    }

    /// Steps already passed (by age) become the target mix, so versions that
    /// don't know the steps compute with the mix that applies now.
    @Test func passedStepsFoldIntoTheTargetMix() {
        var portfolio = PlanPortfolio(targetMix: [.equity: 1], targetMixByAge: [
            TargetMixStep(fromAge: .age(50), mix: [.equity: d("0.9"), .bonds: d("0.1")]),
            TargetMixStep(fromAge: .retirement, mix: [.equity: d("0.6"), .bonds: d("0.4")]),
            TargetMixStep(fromAge: .age(55), mix: [.equity: d("0.7"), .bonds: d("0.3")]),
            TargetMixStep(fromAge: .age(75), mix: [.bonds: 1]),
        ])
        var unchanged = portfolio
        unchanged.foldTargetMixSteps(passedBy: 45)
        #expect(unchanged == portfolio)

        portfolio.foldTargetMixSteps(passedBy: 56)
        // The step from 55 is in force whatever the retirement age; the
        // retirement step before it can't apply any more.
        #expect(portfolio.targetMix == [.equity: d("0.7"), .bonds: d("0.3")])
        #expect(portfolio.targetMixByAge == [TargetMixStep(fromAge: .age(75), mix: [.bonds: 1])])
    }
}
