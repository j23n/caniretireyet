import Model
import Planner
import SwiftUI

// Controls shared by the plan editors: number fields, issue rows, the
// collapsible section card and a sheet for editing one item of a list.

/// A number typed by hand: an amount, a percentage (typed as 4,5 for 4.5%)
/// or a whole number. The value changes as you type valid text; leaving
/// the field shows the value again. An empty field is `nil` if `isOptional`.
struct PlanNumberField: View {
    let title: String
    @Binding var value: Decimal?
    var kind: PlanNumberText.Kind = .amount
    var prompt: String = ""
    var isOptional = false

    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.locale) private var locale

    init(_ title: String, value: Binding<Decimal?>, kind: PlanNumberText.Kind = .amount, prompt: String = "",
         isOptional: Bool = false) {
        self.title = title
        _value = value
        self.kind = kind
        self.prompt = prompt
        self.isOptional = isOptional
    }

    /// A field for a value that's always set: an empty field keeps it.
    init(_ title: String, value: Binding<Decimal>, kind: PlanNumberText.Kind = .amount, prompt: String = "") {
        self.init(title, value: Binding(value), kind: kind, prompt: prompt, isOptional: false)
    }

    var body: some View {
        TextField(title, text: $text, prompt: Text(prompt))
            .labelsHidden()
            .focused($isFocused)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .privacySensitive(kind == .amount)
            #if os(iOS)
            .keyboardType(kind == .integer ? .numberPad : .decimalPad)
            #endif
            .onAppear {
                text = PlanNumberText.text(value, kind: kind, locale: locale)
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = PlanNumberText.text(newValue, kind: kind, locale: locale) }
            }
            .onChange(of: text) { _, newText in
                guard isFocused else { return }
                switch PlanNumberText.parse(newText, kind: kind, locale: locale) {
                case .value(let number):
                    if number != value { value = number }
                case .empty:
                    if isOptional, value != nil { value = nil }
                case .invalid:
                    break
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { text = PlanNumberText.text(value, kind: kind, locale: locale) }
            }
    }
}

/// A labelled number field in a form row, with a unit after it.
struct PlanNumberRow: View {
    let title: String
    @Binding var value: Decimal?
    var kind: PlanNumberText.Kind = .amount
    var unit: String?
    var prompt: String = ""
    var isOptional = false

    init(_ title: String, value: Binding<Decimal?>, kind: PlanNumberText.Kind = .amount, unit: String? = nil,
         prompt: String = "", isOptional: Bool = true) {
        self.title = title
        _value = value
        self.kind = kind
        self.unit = unit
        self.prompt = prompt
        self.isOptional = isOptional
    }

    init(_ title: String, value: Binding<Decimal>, kind: PlanNumberText.Kind = .amount, unit: String? = nil,
         prompt: String = "") {
        self.init(title, value: Binding(value), kind: kind, unit: unit, prompt: prompt, isOptional: false)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: Metrics.xs) {
                PlanNumberField(title, value: $value, kind: kind, prompt: prompt, isOptional: isOptional)
                    .frame(maxWidth: 140)
                if let unit {
                    Text(unit)
                        .foregroundStyle(Palette.secondaryInk)
                }
            }
        } label: {
            Text(title)
        }
    }
}

/// One problem: ⚠︎ for a warning, ⛔︎ for an error that stops the plan.
struct PlanIssueLine: View {
    let message: String
    let isError: Bool

    init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }

    init(_ issue: PlanIssue) {
        self.init(message: issue.message, isError: issue.isError)
    }

    var body: some View {
        Label {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isError ? Palette.critical : Palette.warning)
        }
        .accessibilityLabel(Text("\(isError ? "Error" : "Warning"): \(message)"))
    }
}

/// A count of problems, for a card's header: "⚠︎ 1".
struct PlanIssueBadge: View {
    let issues: [PlanIssue]

    var body: some View {
        let errors = issues.filter(\.isError).count
        let spoken: String = errors > 0 ? "\(issues.count) problems, \(errors) stopping the plan"
            : "\(issues.count) warnings"
        if !issues.isEmpty {
            Label(String(issues.count), systemImage: errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(errors > 0 ? Palette.critical : Palette.warning)
                .accessibilityLabel(Text(spoken))
        }
    }
}

/// A collapsible card of the Inputs form: a title and a one-line summary
/// when collapsed, the editor when expanded (UI.md, "Inputs").
struct PlanSectionCard<Content: View>: View {
    let section: PlanInputSection
    let summary: String
    /// Every issue on the section, counted in the header.
    let issues: [PlanIssue]
    /// The issues listed under the editor: those its rows don't show.
    let listedIssues: [PlanIssue]
    @Binding var isExpanded: Bool
    private let content: Content

    init(section: PlanInputSection, summary: String, issues: [PlanIssue], listedIssues: [PlanIssue]? = nil,
         isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.section = section
        self.summary = summary
        self.issues = issues
        self.listedIssues = listedIssues ?? issues
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.m) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(hint))
            if isExpanded {
                VStack(alignment: .leading, spacing: Metrics.m) {
                    content
                    ForEach(listedIssues, id: \.self) { issue in
                        PlanIssueLine(issue)
                    }
                }
            }
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
    }

    private var hint: String {
        isExpanded ? "Collapses the section" : "Shows the section's inputs"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: section.systemImage)
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if !isExpanded {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .lineLimit(2)
                        .privacySensitive()
                }
            }
            Spacer(minLength: Metrics.s)
            PlanIssueBadge(issues: issues)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.mutedInk)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

/// A row of a list inside a card (a work phase, a pension, an event):
/// a title, a detail line and any problems, opening its editor on tap.
struct PlanListRow: View {
    let title: String
    let detail: String
    var issues: [PlanIssue] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                            .privacySensitive()
                    }
                    ForEach(issues, id: \.self) { issue in
                        PlanIssueLine(issue)
                    }
                }
                Spacer(minLength: Metrics.s)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Palette.mutedInk)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Metrics.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A sheet editing a copy of one item; *Done* hands it back, *Delete*
/// removes it. Once the item is changed, swiping the sheet down does
/// nothing: *Cancel* discards the change.
struct PlanItemEditor<Item: Equatable, Content: View>: View {
    let title: String
    let onSave: (Item) -> Void
    let onDelete: (() -> Void)?
    private let content: (Binding<Item>) -> Content

    @State private var item: Item
    /// The item as the sheet opened with it.
    @State private var original: Item
    @Environment(\.dismiss) private var dismiss

    init(_ title: String, item: Item, onSave: @escaping (Item) -> Void, onDelete: (() -> Void)? = nil,
         @ViewBuilder content: @escaping (Binding<Item>) -> Content) {
        self.title = title
        self.onSave = onSave
        self.onDelete = onDelete
        self.content = content
        _item = State(initialValue: item)
        _original = State(initialValue: item)
    }

    var body: some View {
        NavigationStack {
            Form {
                content($item)
                if let onDelete {
                    Section {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(item)
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(item != original)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }
}

#Preview("Controls") {
    @Previewable @State var amount: Decimal = 36_000
    Form {
        PlanNumberRow("Spending", value: $amount, unit: "/yr")
        PlanIssueLine(message: "Set the tax rate on investment income and gains.", isError: true)
    }
    .formStyle(.grouped)
    .previewEnvironment()
}
