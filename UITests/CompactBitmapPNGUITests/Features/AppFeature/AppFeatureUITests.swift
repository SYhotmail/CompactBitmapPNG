import XCTest

@MainActor
final class CompactBitmapPNGUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    func testMainControlsAreVisible() throws {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Compression"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["clear-results-button"].exists)
        XCTAssertTrue(app.checkBoxes["enable-png-compression-toggle"].exists)
        XCTAssertTrue(app.checkBoxes["enable-pdf-check-toggle"].exists)
        XCTAssertTrue(app.checkBoxes["overwrite-original-files-toggle"].exists)
        XCTAssertTrue(app.staticTexts["Quantization"].exists)
        XCTAssertTrue(app.buttons["256 colors"].exists)
        XCTAssertTrue(app.buttons["128 colors"].exists)
        XCTAssertTrue(app.buttons["64 colors"].exists)
    }

    func testQuantizationDefaultsToActiveAndCanBeDeselected() throws {
        let app = launchApp()

        let colors256Button = app.buttons["256 colors"]
        XCTAssertTrue(colors256Button.waitForExistence(timeout: 5))
        XCTAssertTrue(staticText(
            "Lossless PNG optimization will run first, then the selected lossy quantization level will be tried and only kept if it makes the file smaller.",
            in: app
        ).exists)

        colors256Button.click()

        XCTAssertTrue(staticText("Only lossless PNG optimization will run.", in: app).waitForExistence(timeout: 5))
    }

    /// `app.staticTexts["…"]` uses a fast identifier-lookup path capped at 128 characters, which
    /// the longer quantization descriptions in this app exceed — match by predicate instead,
    /// which has no such limit. SwiftUI `Text` on macOS exposes its content via the AX `value`
    /// attribute rather than `label`, so check both.
    private func staticText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }
}
