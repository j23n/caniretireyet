import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import CanIRetireYet

/// Hiding amounts and the person's data (App/README.md, "Hiding amounts" and
/// "Feedback"): the eye hides an amount wherever it sits, also inside a view
/// marked for feedback, and leaves the person's other data readable; a
/// feedback screenshot hides both. Each view is drawn with `ImageRenderer`
/// and compared, pixel for pixel, with one whose look is known.
@MainActor
struct PrivacyRedactionTests {
    private var amount: some View { Text(verbatim: "123.456 €").privacySensitiveAmount() }
    private var name: some View { Text(verbatim: "Brokerage") }

    @Test func theEyeHidesAnAmountInsideAViewMarkedForFeedback() throws {
        let marked = try pixels(of: amount.privacySensitiveInFeedback().redacted(reason: .privacy))
        #expect(try marked == pixels(of: amount.redacted(reason: .privacy)))
        #expect(try marked != pixels(of: amount))
    }

    @Test func theEyeLeavesTheOtherDataReadable() throws {
        let marked = try pixels(of: name.privacySensitiveInFeedback().redacted(reason: .privacy))
        #expect(try marked == pixels(of: name))
    }

    @Test func aFeedbackScreenshotHidesTheOtherData() throws {
        let marked = try pixels(of: name.privacySensitiveInFeedback()
            .environment(\.hidesPersonalData, true)
            .redacted(reason: .privacy))
        #expect(try marked != pixels(of: name))
    }

    @Test func aFeedbackScreenshotHidesAnAmountInsideAViewMarkedForFeedback() throws {
        let marked = try pixels(of: amount.privacySensitiveInFeedback()
            .environment(\.hidesPersonalData, true)
            .redacted(reason: .privacy))
        #expect(try marked != pixels(of: amount))
    }

    /// The view drawn at 2×, as its size and bytes.
    private func pixels(of view: some View) throws -> Pixels {
        let renderer = ImageRenderer(content: view.padding(4))
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "The view couldn't be drawn.")
        let data = try #require(image.dataProvider?.data as Data?, "The picture has no bytes.")
        return Pixels(width: image.width, height: image.height, bytes: data)
    }

    private struct Pixels: Equatable {
        let width: Int
        let height: Int
        let bytes: Data
    }
}
