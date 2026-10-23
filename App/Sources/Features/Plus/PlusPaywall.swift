import StoreKit
import SwiftUI

/// The paywall (UI.md, "Plus"): what Plus adds, the yearly subscription
/// with its free month for new subscribers and the lifetime purchase at the
/// App Store's prices, and *Restore Purchases*. It opens from an action
/// that needs Plus (``PlusStore/unlock(_:then:)``) or from Settings, never
/// at first launch. It closes once Plus is bought.
struct PlusPaywall: View {
    /// What it was opened for; `nil` from Settings.
    var feature: PlusFeature?

    @Environment(PlusStore.self) private var plus
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss
    /// The product being bought.
    @State private var buying: PlusProduct?
    @State private var isRestoring = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.xl) {
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        Text(feature?.title ?? "Plus")
                            .font(.title2.bold())
                            .foregroundStyle(Palette.ink)
                        Text("Tracking, check-ins, import, widgets and one plan with its answer are free. "
                            + "Plus adds what you need to plan more than one future.")
                            .foregroundStyle(Palette.secondaryInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.m) {
                        ForEach(PlusFeatureLine.all) { line in
                            PlusFeatureRow(line: line)
                        }
                    }
                    purchaseButtons
                    VStack(alignment: .leading, spacing: Metrics.s) {
                        if let message {
                            Text(message)
                                .foregroundStyle(Palette.ink)
                        }
                        Text("Yearly renews each year until you cancel it in your Apple Account's subscriptions. "
                            + "Your plans and files are yours either way: if Plus ends, they open as before, "
                            + "and only what Plus adds locks again.")
                            .foregroundStyle(Palette.secondaryInk)
                        Button("Restore Purchases") { restore() }
                            .buttonStyle(.borderless)
                            .disabled(isRestoring || buying != nil)
                    }
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Metrics.l)
                .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.page)
            .navigationTitle("Plus")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .task { await plus.loadPrices() }
            .onChange(of: plus.hasPlus) { _, hasPlus in
                // Bought here, restored, or approved while the paywall was open.
                if hasPlus { dismiss() }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 520)
        #endif
    }

    /// Yearly first, with its free month when this person may have it,
    /// then lifetime.
    @ViewBuilder
    private var purchaseButtons: some View {
        if let prices = plus.prices {
            VStack(spacing: Metrics.m) {
                Button {
                    buy(.yearly)
                } label: {
                    PlusPriceLabel(title: "Yearly", detail: Self.yearlyDetail(prices), isBuying: buying == .yearly)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    buy(.lifetime)
                } label: {
                    PlusPriceLabel(title: "Lifetime", detail: "\(prices.lifetime) once", isBuying: buying == .lifetime)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(buying != nil || isRestoring)
        } else {
            HStack(spacing: Metrics.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Asking the App Store for prices…")
                    .foregroundStyle(Palette.secondaryInk)
            }
            .font(.footnote)
        }
    }

    /// "First month free, then 34,99 € a year", or "34,99 € a year" for
    /// someone who has had the free month.
    static func yearlyDetail(_ prices: PlusPrices) -> String {
        if let freeTrial = prices.freeTrial {
            "First \(freeTrial) free, then \(prices.yearly) a year"
        } else {
            "\(prices.yearly) a year"
        }
    }

    private func buy(_ kind: PlusProduct) {
        guard let product = plus.product(kind) else { return }
        buying = kind
        message = nil
        Task {
            defer { buying = nil }
            do {
                let result = try await purchase(product)
                if try await plus.complete(result) { dismiss() }
            } catch {
                message = error.localizedDescription
            }
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

/// One thing Plus adds, as the paywall lists it.
private struct PlusFeatureLine: Identifiable {
    var symbol: String
    var title: String
    var detail: String

    var id: String { title }

    /// What Plus adds, in the paywall's order.
    static let all = [
        PlusFeatureLine(symbol: "square.stack.3d.up", title: "More plans",
                        detail: "Keep other lives next to your main plan, such as part-time from 50, "
                            + "and duplicate one to change a thing."),
        PlusFeatureLine(symbol: "slider.horizontal.3", title: "What if",
                        detail: "Try a change before you make it in the plan."),
        PlusFeatureLine(symbol: "bookmark", title: "Baselines",
                        detail: "Save what you expect now, or what you planned years ago, "
                            + "and measure your progress against it."),
        PlusFeatureLine(symbol: "function", title: "Export Calculations",
                        detail: "Every calculation behind an answer, to check it or give to someone else."),
    ]
}

/// One thing Plus adds: a symbol, its name and a line.
private struct PlusFeatureRow: View {
    let line: PlusFeatureLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.m) {
            Image(systemName: line.symbol)
                .foregroundStyle(Palette.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
                Text(line.detail)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A purchase button's label: the product and its price, or progress while
/// it's being bought.
private struct PlusPriceLabel: View {
    let title: String
    let detail: String
    let isBuying: Bool

    var body: some View {
        VStack(spacing: 2) {
            if isBuying {
                ProgressView()
            } else {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.footnote)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.xs)
    }
}

#Preview("Paywall") {
    PlusPaywall(feature: .whatIf)
        .environment(PlusStore(access: .free, prices: .sample))
}

#Preview("Paywall, trial used") {
    PlusPaywall(feature: .morePlans)
        .environment(PlusStore(access: .free, prices: PlusPrices(yearly: "34,99 €", lifetime: "99,99 €")))
}
