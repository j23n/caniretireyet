import Model
import SwiftUI
import Testing
@testable import CanIRetireYet
#if os(iOS)
import UIKit
#endif

/// The main screens at the window sizes the app meets: iPhone from the
/// smallest to the largest, in portrait and landscape; a foldable iPhone's
/// inner screen, read both compact and regular; iPad in Slide Over, Split
/// View and full screen; the Mac from its smallest window to a large
/// display. Each size opens one model, calculates its plan once, then
/// shows each screen in turn. On iOS each size is a frame of its own with
/// its size classes, drawn on one large iPad's screen.
@MainActor
@Suite(.serialized)
struct ScreenSizeTests {
    struct Size: CustomTestStringConvertible, Sendable {
        let name: String
        let width: CGFloat
        let height: CGFloat
        /// iOS: whether the width is regular (the sidebar) or compact (tabs).
        var regular = false
        /// iOS: whether the height is compact (iPhone in landscape).
        var compactHeight = false

        var testDescription: String { name }
    }

    #if os(iOS)
    static let sizes: [Size] = [
        Size(name: "320x568-se-slideover", width: 320, height: 568),
        Size(name: "375x667-se3", width: 375, height: 667),
        Size(name: "402x874-pro", width: 402, height: 874),
        Size(name: "440x956-promax", width: 440, height: 956),
        Size(name: "874x402-pro-landscape", width: 874, height: 402, compactHeight: true),
        Size(name: "956x440-promax-landscape", width: 956, height: 440, regular: true, compactHeight: true),
        Size(name: "690x880-fold-compact", width: 690, height: 880),
        Size(name: "820x1000-fold-regular", width: 820, height: 1000, regular: true),
        Size(name: "507x1000-ipad-split-half", width: 507, height: 1000),
        Size(name: "744x1133-ipad-mini", width: 744, height: 1133, regular: true),
        Size(name: "1032x1376-ipad-13", width: 1032, height: 1376, regular: true),
    ]
    #else
    static let sizes: [Size] = [
        Size(name: "900x600-min", width: 900, height: 600),
        Size(name: "1440x900", width: 1440, height: 900),
        Size(name: "2200x1300-large", width: 2200, height: 1300),
    ]
    #endif

    @Test(arguments: sizes)
    func screens(at size: Size) async throws {
        let launch = ScreenLaunch(.example, screen: .today)
        let main = try #require(launch.library.settings.mainPlan)
        let model = launch.model()
        let window = try SizedWindow(root(model), size: size)
        defer { window.close() }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(240)
        while model.plans.results(of: main) == nil && model.plans.errors[main] == nil && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
        }
        let navigation = model.navigation
        let screens: [(String, () -> Void)] = [
            ("today", { navigation.showToday() }),
            ("plan", { navigation.showPlan(main) }),
            ("year", { navigation.showTimeline(.year) }),
            ("decades", { navigation.showTimeline(.decades) }),
            ("lookback", { navigation.showTimeline(.lookBack) }),
            ("account", { navigation.showToday(); navigation.showAccount("conto-fineco") }),
        ]
        try FileManager.default.createDirectory(at: ScreenCapture.folder, withIntermediateDirectories: true)
        for (name, show) in screens {
            show()
            try await Task.sleep(for: .seconds(2))
            let png = try #require(window.png(), "\(size.name) \(name): the window couldn't be drawn.")
            try png.write(to: ScreenCapture.folder.appendingPathComponent(
                "\(ScreenCapture.platform)-size-\(size.name)-\(name).png"))
        }
    }

    @ViewBuilder
    private func root(_ model: AppModel) -> some View {
        #if os(macOS)
        FixedMinimumSize(minWidth: 900, minHeight: 600) {
            RootView()
        }
        .appEnvironment(model)
        .task { await model.start() }
        #else
        RootView()
            .appEnvironment(model)
            .task { await model.start() }
        #endif
    }
}

#if os(macOS)
@MainActor
private final class SizedWindow {
    private let window: CaptureWindow

    init(_ view: some View, size: ScreenSizeTests.Size) throws {
        window = try CaptureWindow(view, size: CGSize(width: size.width, height: size.height))
    }

    func png() -> Data? { window.png() }
    func close() { window.close() }
}
#else
/// The view in a frame of `size` at the top left of a window over the
/// app's, with the size's size classes, as a device of that size has them.
@MainActor
private final class SizedWindow {
    private let window: UIWindow
    private let host: UIViewController

    init(_ view: some View, size: ScreenSizeTests.Size) throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene: the screen tests run inside the app.")
        window = UIWindow(windowScene: scene)
        let container = UIViewController()
        container.view.backgroundColor = .black
        let host = UIHostingController(rootView: view)
        host.traitOverrides.horizontalSizeClass = size.regular ? .regular : .compact
        host.traitOverrides.verticalSizeClass = size.compactHeight ? .compact : .regular
        container.addChild(host)
        host.view.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        host.view.autoresizingMask = []
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        self.host = host
        window.rootViewController = container
        window.makeKeyAndVisible()
    }

    func png() -> Data? {
        let view = host.view!
        return UIGraphicsImageRenderer(bounds: view.bounds).pngData { _ in
            _ = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
    }

    func close() {
        window.isHidden = true
    }
}
#endif
