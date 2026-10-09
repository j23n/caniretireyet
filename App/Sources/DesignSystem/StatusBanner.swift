import CloudSync
import Storage
import SwiftUI

/// A calm status message: an icon, a title and a sentence, with an optional
/// action. Status colours only ever appear with the icon and the words
/// (UI.md, "Status colours"); nothing here scolds.
///
///     StatusBanner(.warning, "Fondo pensione: last value in May")
///     StatusBanner(.info, "Read-only", message: "…", action: ("Learn more", { … }))
struct StatusBanner: View {
    enum Kind: Hashable, Sendable {
        case info
        case success
        case warning
        case error

        var systemImage: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .error: "xmark.octagon"
            }
        }

        var color: Color {
            switch self {
            case .info: Palette.accent
            case .success: Palette.good
            case .warning: Palette.warning
            case .error: Palette.critical
            }
        }
    }

    let kind: Kind
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ kind: Kind, _ title: String, message: String? = nil, actionTitle: String? = nil,
         action: (() -> Void)? = nil) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.xs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius / 1.5, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The library's own state as banners: read-only, a failed save, files that
/// couldn't be read, conflicts that were merged or failed, and files a save
/// copied to backups or kept because they changed elsewhere. Shows nothing
/// when all is well. Screens put it at the top of their content; the
/// Overview shows it in "Needs attention".
struct LibraryStatusBanners: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigation.self) private var navigation

    /// Whether there's a banner to show: the body's conditions, for a
    /// screen that shows the banners in a card of its own (the Overview's
    /// "Needs attention").
    static func showsAny(for library: LibraryStore) -> Bool {
        library.isReadOnly || library.lastError != nil || library.loadIssues.contains { $0.severity == .error }
            || !library.mergedConflicts.isEmpty || !library.conflictFailures.isEmpty || !library.saveNotices.isEmpty
    }

    var body: some View {
        VStack(spacing: Metrics.s) {
            if let reason = library.readOnlyReason {
                StatusBanner(.info, "Read-only", message: LibraryStoreError.readOnly(reason).message)
            }
            if let error = library.lastError {
                StatusBanner(.error, "Something went wrong with the library", message: error,
                             actionTitle: "Dismiss") { library.dismissError() }
            }
            let errors = library.loadIssues.filter { $0.severity == .error }
            if !errors.isEmpty {
                StatusBanner(
                    .warning, errors.count == 1 ? "A file couldn't be read" : "\(errors.count) files couldn't be read",
                    message: errors.prefix(3).map(\.description).joined(separator: "\n"),
                    actionTitle: "Show details") { navigation.show(.sync) }
            }
            if !library.mergedConflicts.isEmpty {
                let count = library.mergedConflicts.count
                StatusBanner(
                    .info, count == 1 ? "A sync conflict was merged" : "\(count) sync conflicts were merged",
                    message: library.mergedConflicts.first?.summary, actionTitle: "Review") { navigation.show(.sync) }
            }
            if !library.conflictFailures.isEmpty {
                StatusBanner(
                    .warning, "A sync conflict couldn't be merged",
                    message: library.conflictFailures.map(\.path).joined(separator: ", "),
                    actionTitle: "Show details") { navigation.show(.sync) }
            }
            if !library.saveNotices.isEmpty {
                let count = library.saveNotices.count
                StatusBanner(
                    .warning, count == 1 ? "Saving found a file changed elsewhere"
                        : "Saving found \(count) files changed elsewhere",
                    message: library.saveNotices.first?.summary, actionTitle: "Review") { navigation.show(.sync) }
            }
        }
    }
}

#Preview("Banners") {
    VStack(spacing: Metrics.m) {
        StatusBanner(.warning, "Fondo pensione: last value in May", message: "Update it at your next check-in.")
        StatusBanner(.info, "A sync conflict was merged", message: "Merged 2 versions of history for 2026-09.",
                     actionTitle: "Review") {}
        StatusBanner(.error, "Couldn't save your changes", message: "The disk is full.")
        StatusBanner(.success, "Saved")
        LibraryStatusBanners()
    }
    .padding()
    .background(Palette.page)
    .previewEnvironment()
}
