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
        XCTAssertTrue(app.buttons["Choose Files"].exists)
        XCTAssertTrue(app.buttons["Choose Folder"].exists)
        XCTAssertTrue(app.buttons["Clear Results"].exists)
        XCTAssertTrue(app.staticTexts["Enable PNG compression"].exists)
        XCTAssertTrue(app.staticTexts["Enable PDF check"].exists)
        XCTAssertTrue(app.staticTexts["Enable lossy PNG quantization"].exists)
        XCTAssertTrue(app.staticTexts["Only lossless PNG optimization will run. Quantization is off by default."].exists)
    }

    @MainActor
    func testQuantizationUIAppearsWhenLaunchedEnabled() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITestEnableQuantization")
        app.launch()

        XCTAssertTrue(app.staticTexts["Quantization target"].waitForExistence(timeout: 5))
    }
}
