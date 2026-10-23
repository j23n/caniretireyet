import SwiftUI

/// Settings' Plus section (UI.md, "Plus"): whether this person has Plus and
/// until when, *Get Plus…* (the paywall) without it, and *Restore Purchases*.
struct PlusSection: View {
    @Environment(PlusStore.self) private var plus
    @State private var showsPaywall = false
    @State private var isRestoring = false
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("Plus") {
                // The person's own subscription dates.
                Text(Self.status(plus.access))
                    .privacySensitiveInFeedback()
            }
            // On a row that stays, not on the section, whose modifiers go
            // to each row. Its own sheet: on iPhone and iPad Settings is a
            // sheet itself, and on the Mac a window of its own.
            .sheet(isPresented: $showsPaywall) {
                PlusPaywall()
            }
            if !plus.hasPlus {
                Button("Get Plus…") { showsPaywall = true }
            }
            Button("Restore Purchases") { restore() }
                .disabled(isRestoring)
        } header: {
            Text("Plus")
        } footer: {
            Text(message ?? "Plus adds more plans, What if, baselines and Export Calculations. "
                + "Your library's files never depend on it.")
        }
    }

    /// "Lifetime", "Yearly, renews 3 Oct 2027", "Free month, until 3 Nov 2026", "Not yet";
    /// "Yearly, renewal pending" in a Billing Grace Period, whose period has ended.
    static func status(_ access: PlusAccess, at now: Date = .now) -> String {
        switch access {
        case .free: "Not yet"
        case let .trial(end) where end <= now, let .yearly(end) where end <= now: "Yearly, renewal pending"
        case let .trial(endsAt): "Free month, until \(endsAt.formatted(date: .abbreviated, time: .omitted))"
        case let .yearly(renewsAt): "Yearly, renews \(renewsAt.formatted(date: .abbreviated, time: .omitted))"
        case .lifetime: "Lifetime"
        }
    }

    private func restore() {
        isRestoring = true
        message = nil
        Task {
            message = await plus.restore()
            isRestoring = false
        }
    }
}
