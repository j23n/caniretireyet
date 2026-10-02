import CloudSync
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The screen while the library opens (UI.md, "Opening the library"), from
/// `LibraryStore.opening`.
struct LibraryOpeningView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        LibraryOpeningContent(
            opening: library.opening,
            tryAgain: { Task { await library.start() } },
            keepWaiting: { library.keepWaiting() })
    }
}

/// What opening the library is doing: the step, with a progress bar while
/// files download from iCloud Drive. Once nothing has moved for a while, it
/// says why that may be and offers Try Again and Keep Waiting, and Open
/// Settings on iPhone and iPad. It never offers to create a library: one
/// that exists but hasn't arrived would be duplicated.
struct LibraryOpeningContent: View {
    let opening: LibraryOpening
    let tryAgain: () -> Void
    let keepWaiting: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Metrics.xl) {
                    if opening.isStalled {
                        stalled
                    } else {
                        progress
                    }
                }
                .frame(maxWidth: 480)
                .padding(Metrics.xl)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Palette.page)
    }

    /// The step, with a bar while downloading.
    private var progress: some View {
        VStack(spacing: Metrics.m) {
            if let fraction = opening.fractionCompleted {
                Text(opening.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel(opening.title)
                if let detail = opening.detail {
                    Text(detail)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondaryInk)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(opening.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            if let failure = opening.failureNote {
                Text(failure)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondaryInk)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Why it may be stuck, and what to do.
    private var stalled: some View {
        VStack(alignment: .leading, spacing: Metrics.l) {
            Label(opening.stalledTitle, systemImage: opening.isICloud ? "icloud.slash" : "hourglass")
                .font(.title2.weight(.semibold))
            Text(opening.stalledMessage)
            if opening.fractionCompleted != nil || opening.failureNote != nil {
                progress
                    .padding(Metrics.l)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: Metrics.cardRadius))
            }
            if !reasons.isEmpty {
                VStack(alignment: .leading, spacing: Metrics.s) {
                    Text("This can happen when:")
                    ForEach(reasons, id: \.self) { reason in
                        HStack(alignment: .firstTextBaseline, spacing: Metrics.s) {
                            Text("•")
                                .accessibilityHidden(true)
                            Text(reason)
                        }
                    }
                }
                .foregroundStyle(Palette.secondaryInk)
            }
            VStack(spacing: Metrics.m) {
                Button(action: tryAgain) {
                    Text("Try Again")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: keepWaiting) {
                    Text("Keep Waiting")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                #if os(iOS)
                OpenSettingsButton()
                #endif
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reasons: [String] {
        #if os(macOS)
        opening.stalledReasons(onMac: true)
        #else
        opening.stalledReasons(onMac: false)
        #endif
    }
}

#if os(iOS)
/// Opens the app's page in Settings.
private struct OpenSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            Text("Open Settings")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
#endif

#Preview("Looking") {
    LibraryOpeningContent(
        opening: LibraryOpening(step: .looking(.iCloud), isICloud: true), tryAgain: {}, keepWaiting: {})
}

#Preview("Downloading") {
    LibraryOpeningContent(
        opening: LibraryOpening(
            step: .downloading(LibraryDownloadProgress(
                isListed: true, totalFiles: 150, filesToDownload: 140, downloadedFiles: 52,
                bytesToDownload: 3_400_000, downloadedBytes: 1_250_000)),
            isICloud: true),
        tryAgain: {}, keepWaiting: {})
}

#Preview("Still waiting") {
    LibraryOpeningContent(
        opening: LibraryOpening(
            step: .downloading(LibraryDownloadProgress(
                isListed: true, totalFiles: 150, filesToDownload: 140, downloadedFiles: 52,
                failures: [LibraryDownloadFailure(
                    path: "history/2019/2019-03.json", message: "The Internet connection appears to be offline.")])),
            isICloud: true, isStalled: true),
        tryAgain: {}, keepWaiting: {})
}
