import Foundation
import SwiftUI
import Testing
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shows a view in a window of its own, waits until it's ready, and keeps a
/// picture of the window as a PNG: `<platform>-<name>.png` in ``folder``.
/// No UI automation: the tests run inside the app (its test host) and draw
/// its windows themselves.
@MainActor
enum ScreenCapture {
    /// Where the pictures go: `SCREENSHOTS_DIR` (`make screenshots` sets
    /// it), else `.build/screenshots` at the repository's root.
    static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        // App/ScreenTests/ScreenCapture.swift: three levels up is the repository.
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/screenshots", isDirectory: true)
    }

    /// The pictures' prefix: `mac` or `iphone`.
    static var platform: String {
        #if os(macOS)
        return "mac"
        #else
        return "iphone"
        #endif
    }

    /// Shows `view` (on the Mac in a window of `size`; on iPhone full
    /// screen), waits until `ready` (at most `timeout`), lets it settle for
    /// `settle`, and keeps its picture. A screen that never gets ready is
    /// an issue, and its picture is kept all the same.
    static func keep(_ view: some View, named name: String, size: CGSize = CGSize(width: 1_200, height: 800),
                     timeout: Duration = .seconds(240), settle: Duration = .seconds(2),
                     until ready: () -> Bool) async throws {
        let window = try CaptureWindow(view, size: size)
        defer { window.close() }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !ready() {
            guard clock.now < deadline else {
                Issue.record(Comment(rawValue: "\(name): the screen wasn't ready after \(timeout)."))
                break
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: settle)
        let png = try #require(window.png(), Comment(rawValue: "\(name): the window couldn't be drawn."))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png.write(to: folder.appendingPathComponent("\(platform)-\(name).png"))
    }
}

#if os(macOS)
/// A Mac window holding the view, with its title and toolbar, as the app's own.
@MainActor
private final class CaptureWindow {
    private let window: NSWindow

    init(_ view: some View, size: CGSize) throws {
        let controller = NSHostingController(rootView: view)
        controller.sceneBridgingOptions = [.title, .toolbars]
        controller.sizingOptions = [.minSize]
        window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
    }

    /// The whole window, its title bar and toolbar too.
    func png() -> Data? {
        guard let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    func close() {
        window.close()
    }
}
#else
/// A window over the app's own, on its scene: the whole screen.
@MainActor
private final class CaptureWindow {
    private let window: UIWindow

    init(_ view: some View, size: CGSize) throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "No window scene: the screen tests run inside the app.")
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
    }

    func png() -> Data? {
        let window = window
        return UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    func close() {
        window.isHidden = true
    }
}
#endif
