import SwiftUI

// Hiding amounts (UI.md, "Privacy"), the same way in the app and its widgets:
// SwiftUI's redaction. The app redacts its windows for `.privacy` while the
// eye is on (`appEnvironment`), and WidgetKit does on a locked device. A view
// that shows an amount on its own marks it `.privacySensitive()`, so it draws
// as a placeholder; a sentence with amounts in it is an `AmountSentenceText`,
// whose amounts draw as placeholders while its words stay. Compiled into the
// app and the widgets.

extension RedactionReasons {
    /// Whether amounts are hidden: the view is redacted for `.privacy`. The
    /// eye button in the app (also while a feedback screenshot is taken), a
    /// locked device in the widgets.
    var hidesAmounts: Bool {
        contains(.privacy)
    }
}

extension View {
    /// An amount shown on its own (a figure, a table cell, a quantity): it
    /// draws as a placeholder while amounts are hidden (`.privacySensitive()`),
    /// and VoiceOver reads "Amount hidden". ``AmountText`` does this itself.
    func privacySensitiveAmount() -> some View {
        modifier(PrivacySensitiveAmount())
    }
}

private struct PrivacySensitiveAmount: ViewModifier {
    @Environment(\.redactionReasons) private var redactionReasons

    func body(content: Content) -> some View {
        if redactionReasons.hidesAmounts {
            content
                .privacySensitive()
                .accessibilityLabel(Text("Amount hidden"))
        } else {
            content
                .privacySensitive()
        }
    }
}

/// A sentence with amounts in it, as one text that wraps as text does.
/// While amounts are hidden (`redactionReasons.hidesAmounts`), each amount
/// draws as a placeholder, as `.privacySensitive()` views do, and the words
/// stay; VoiceOver reads "amount hidden" in its place. While a feedback
/// screenshot is taken (`hidesPersonalData`) the words draw as placeholders
/// too, since they hold names, ages, years and dates from the person's data.
///
///     AmountSentenceText("You saved \(amount: saved) and markets added \(amount: markets).")
///         .font(.footnote)
struct AmountSentenceText: View {
    let sentence: AmountSentence

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.hidesPersonalData) private var hidesPersonalData

    init(_ sentence: AmountSentence) {
        self.sentence = sentence
    }

    var body: some View {
        let hides = redactionReasons.hidesAmounts
        Text(sentence: sentence, hidesAmounts: hides, hidesWords: hidesPersonalData)
            .textRenderer(AmountPlaceholderRenderer(hidesAmounts: hides, hidesWords: hidesPersonalData))
            .accessibilityLabel(Text(verbatim: sentence.spoken(hidesAmounts: hides)))
    }
}

extension Text {
    /// `sentence` as one text, each amount tagged (``AmountRun``) and its
    /// words too (``SentenceWordsRun``), so ``AmountPlaceholderRenderer`` can
    /// draw a placeholder in their place. With `hidesAmounts`, the amounts
    /// are also clear, so they don't show where the renderer doesn't draw;
    /// with `hidesWords` (a feedback screenshot), the amounts and the words
    /// are. Views use ``AmountSentenceText``, which adds the renderer.
    /// Labelled, since a string literal can be an `AmountSentence` too.
    init(sentence: AmountSentence, hidesAmounts: Bool = false, hidesWords: Bool = false) {
        var text = Text(verbatim: "")
        for part in sentence.parts {
            switch part {
            case .words(let words):
                let run = Text(verbatim: words).customAttribute(SentenceWordsRun())
                text = Text("\(text)\(hidesWords ? run.foregroundStyle(Color.clear) : run)")
            case .amount(let amount):
                let run = Text(verbatim: amount).customAttribute(AmountRun())
                text = Text("\(text)\(hidesAmounts || hidesWords ? run.foregroundStyle(Color.clear) : run)")
            }
        }
        self = text
    }
}

/// Marks an amount inside a sentence's text (``AmountSentenceText``).
struct AmountRun: TextAttribute {}

/// Marks a sentence's words inside its text (``AmountSentenceText``), which
/// hide in a feedback screenshot: they hold names, ages, years and dates.
/// Words of the app's own around it, such as a title in front, stay.
struct SentenceWordsRun: TextAttribute {}

/// Draws a sentence's text, with a placeholder in place of each amount
/// (``AmountRun``) while amounts are hidden: a rounded bar the amount's
/// width, in the view's foreground colour, faint, as SwiftUI's redaction
/// draws one. With `hidesWords` (a feedback screenshot, `hidesPersonalData`)
/// the sentence's words (``SentenceWordsRun``) draw as placeholders too.
struct AmountPlaceholderRenderer: TextRenderer {
    var hidesAmounts: Bool
    var hidesWords = false

    /// How strong the placeholder's colour is against the text's.
    static let placeholderOpacity = 0.2

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                let isAmount = run[AmountRun.self] != nil
                if (isAmount && (hidesAmounts || hidesWords)) || (hidesWords && run[SentenceWordsRun.self] != nil) {
                    let bounds = run.typographicBounds.rect
                    let bar = bounds.insetBy(dx: 0, dy: bounds.height * 0.18)
                    var placeholder = context
                    placeholder.opacity = Self.placeholderOpacity
                    placeholder.fill(Path(roundedRect: bar, cornerRadius: min(4, bar.height / 3)), with: .foreground)
                } else {
                    context.draw(run)
                }
            }
        }
    }
}
