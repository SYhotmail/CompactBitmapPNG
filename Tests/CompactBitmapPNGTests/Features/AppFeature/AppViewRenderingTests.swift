import AppKit
import ComposableArchitecture
import SwiftUI
import Testing
@testable import CompactBitmapPNG

@Suite("AppView Rendering")
@MainActor
struct AppViewRenderingTests {
    @Test("Content view can be hosted in a window and laid out")
    func canBeHostedAndLaidOut() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 900),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = NSHostingController(
            rootView: AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        )

        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 1024, height: 900)
        controller.view.layoutSubtreeIfNeeded()

        #expect(window.contentViewController === controller)
        #expect(controller.view.frame.width == 1024)
        #expect(controller.view.frame.height == 900)
        #expect(controller.view.fittingSize.width > 0)
        #expect(controller.view.fittingSize.height > 0)
    }

    @Test("Content view renders into a bitmap")
    func rendersIntoBitmap() {
        let controller = NSHostingController(
            rootView: AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        )
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1024, height: 900)
        controller.view.layoutSubtreeIfNeeded()

        guard let bitmap = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else {
            Issue.record("Failed to create bitmap image representation for AppView")
            return
        }

        controller.view.cacheDisplay(in: controller.view.bounds, to: bitmap)

        #expect(bitmap.pixelsWide >= 1024)
        #expect(bitmap.pixelsHigh >= 900)
        #expect(bitmap.representation(using: .png, properties: [:])?.isEmpty == false)
    }
}
