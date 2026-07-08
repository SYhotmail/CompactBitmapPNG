import XCTest

final class PNGCompressorPDFVectorCheckUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testMainControlsAreVisible() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["PNG Compressor + PDF Vector Check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Select Files or Folder…"].exists)
        XCTAssertTrue(app.buttons["Clear Results"].exists)
        XCTAssertTrue(app.staticTexts["Enable PNG compression"].exists)
        XCTAssertTrue(app.staticTexts["Enable PDF check"].exists)
        XCTAssertTrue(app.staticTexts["Quantization"].exists)
        XCTAssertTrue(app.buttons["256 colors"].exists)
        XCTAssertTrue(app.buttons["128 colors"].exists)
        XCTAssertTrue(app.buttons["64 colors"].exists)
    }

    @MainActor
    func testQuantizationDefaultsToActiveAndCanBeDeselected() throws {
        let app = XCUIApplication()
        app.launch()

        let colors256Button = app.buttons["256 colors"]
        XCTAssertTrue(colors256Button.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Lossless PNG optimization will run first, then the selected lossy quantization level will be tried and only kept if it makes the file smaller."].exists)

        colors256Button.click()

        XCTAssertTrue(app.staticTexts["Only lossless PNG optimization will run."].waitForExistence(timeout: 5))
    }
}
