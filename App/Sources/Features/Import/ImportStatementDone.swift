import Foundation
import Model
import SwiftUI

extension EnvironmentValues {
    /// Closes the Import screen when it has an import of its own (a sheet,
    /// or pushed on another flow's stack); `nil` on the Mac and iPad page,
    /// which keeps its import. Bank statements' Done calls it.
    @Entry var importClose: (@MainActor () -> Void)?
}

extension View {
    /// The Import screen's steps along the top and its bar at the bottom:
    /// Review's own bar for bank statements, and neither on their Done,
    /// which is a page of its own (``ImportFlow/showsImportBars``).
    func importBars(model: ImportController) -> some View {
        modifier(ImportBars(model: model))
    }
}

private struct ImportBars: ViewModifier {
    let model: ImportController

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.flow.showsImportBars {
                    ImportStepBar(model: model)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.flow.step == .preview, model.flow.layout == .statement {
                    ImportReviewBottomBar(model: model)
                } else if model.flow.showsImportBars {
                    ImportBottomBar(model: model)
                }
            }
    }
}

/// Bank statements' Done (UI.md, "Import"): a page of its own, centered,
/// with no bars. "Imported 26 months for 3 accounts", what was saved this
/// year, the starting estimates it can replace and the answer
/// (``ImportAnswerFollowUp``), what was remembered for next time, then *Undo Import*, *Open
/// So Far* and *Done*. Undone with later changes kept, it says what stayed.
struct ImportStatementDone: View {
    let model: ImportController
    let receipt: ImportReceipt
    /// Asks before undoing; the Done step holds the dialog.
    let confirmUndo: () -> Void

    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.importClose) private var close
    @Environment(\.locale) private var locale
    @Environment(\.pageLayout) private var layout

    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: receipt.isUndone ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: isCompact ? 64 : 56))
                    .foregroundStyle(receipt.isUndone ? Palette.warning : Palette.good)
                    .accessibilityHidden(true)
                VStack(spacing: Metrics.s) {
                    Text(title)
                        .font(.title.bold())
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    if receipt.isUndone {
                        Text(receipt.undoNotes.joined(separator: "\n"))
                            .font(.callout)
                            .foregroundStyle(Palette.secondaryInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .privacySensitiveInFeedback()
                    } else if let savings = receipt.savings {
                        AmountSentenceText(savings.sentence(locale: locale))
                            .font(isCompact ? .callout : .title3)
                            .foregroundStyle(Palette.secondaryInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ImportAnswerFollowUp(model: model, receipt: receipt)
                if !receipt.isUndone, !receipt.remembered.isEmpty {
                    ImportRememberedCard(items: receipt.remembered)
                }
                buttons
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, isCompact ? Metrics.l : Metrics.xl)
            .padding(.vertical, isCompact ? Metrics.xl : 48)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Palette.page)
        #if os(iOS)
        .toolbar(isCompact ? .hidden : .automatic, for: .navigationBar)
        #endif
    }

    /// "Imported 26 months for 3 accounts".
    private var title: String {
        if receipt.isUndone { return "The import was undone, except for later changes" }
        return receipt.summary ?? "Imported \(receipt.fileName)"
    }

    @ViewBuilder
    private var buttons: some View {
        let canUndo = receipt.canUndo && !model.isWorking && library.canEdit
        if isCompact {
            VStack(spacing: Metrics.m) {
                Button(action: done) {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                HStack(spacing: Metrics.xl) {
                    if receipt.canUndo {
                        Button("Undo Import", action: confirmUndo)
                            .disabled(!canUndo)
                    }
                    Button("Open So Far", action: openSoFar)
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
            .padding(.top, Metrics.s)
        } else {
            HStack(spacing: Metrics.m) {
                if receipt.canUndo {
                    Button("Undo Import", action: confirmUndo)
                        .disabled(!canUndo)
                }
                Button("Open So Far", action: openSoFar)
                Button("Done", action: done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, Metrics.s)
        }
    }

    /// Closes a sheet; the page starts a new import.
    private func done() {
        if let close {
            close()
        } else {
            model.startOver()
        }
    }

    /// So far, with the import in its money in and out: a sheet closes first.
    private func openSoFar() {
        let navigation = navigation
        if let close {
            close()
        } else {
            model.startOver()
        }
        navigation.showSoFar()
    }
}

/// "Remembered for next time": how each new bank's statements are read
/// and the senders' answers, each with what it applies to on a wide screen.
private struct ImportRememberedCard: View {
    let items: [ImportRemembered]
    @Environment(\.pageLayout) private var layout
    private var isCompact: Bool { !layout.isWide }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Remembered for next time")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.secondaryInk)
                .padding(.horizontal, Metrics.l)
                .padding(.top, Metrics.m)
                .padding(.bottom, Metrics.xs)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider()
                        .padding(.leading, Metrics.l)
                }
                HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.good)
                        .accessibilityHidden(true)
                    Text(item.title)
                        .font(.callout)
                        .foregroundStyle(Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isCompact {
                        Text(item.scope)
                            .font(.footnote)
                            .foregroundStyle(Palette.secondaryInk)
                    }
                }
                .padding(.horizontal, Metrics.l)
                .padding(.vertical, Metrics.s + 2)
                .privacySensitiveInFeedback()
            }
        }
        .padding(.bottom, Metrics.xs)
        .cardSurface()
    }
}
