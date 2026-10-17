import XCTest

/// Captures the App Store screenshots from a demo database
/// (-UITestDemoData). Each screenshot is kept in the result bundle as an
/// attachment named after the screen; the screenshots workflow exports
/// them. Not part of the regular test run's assertions beyond reaching
/// each screen.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITest", "-UITestReset", "-UITestDemoData",
            "-autoFillPromptDismissed", "YES",
        ]
        app.launch()
        let driver = AppDriver(app: app, test: self)

        let database = app.buttons["library.database.Personal"]
        XCTAssertTrue(database.waitForExistence(timeout: 30), "The demo database wasn't created")
        capture("01-Library")

        database.tap()
        if app.secureTextFields["unlock.password"].waitForExistence(timeout: 3) {
            driver.unlock(with: AppDriver.password)
        }
        XCTAssertTrue(app.buttons["entry.Cloud Storage"].waitForExistence(timeout: 15), "The database didn't open")
        capture("02-Database")

        app.buttons["entry.Cloud Storage"].tap()
        XCTAssertTrue(app.buttons["entry.edit"].waitForExistence(timeout: 5), "The entry didn't open")
        capture("03-Entry")

        app.buttons["entry.edit"].tap()
        let generate = app.buttons["editor.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5), "The editor didn't open")
        generate.tap()
        XCTAssertTrue(app.descendants(matching: .any)["generator.value"].waitForExistence(timeout: 5))
        capture("04-Generator")

        // Relaunch to leave the editor without saving, keeping the database.
        app.terminate()
        app.launchArguments = ["-UITest", "-autoFillPromptDismissed", "YES"]
        app.launch()
        XCTAssertTrue(database.waitForExistence(timeout: 15))
        database.tap()
        if app.secureTextFields["unlock.password"].waitForExistence(timeout: 5) {
            driver.unlock(with: AppDriver.password)
        }
        let search = app.textFields["group.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15), "The database didn't open again")
        search.tap()
        search.typeText("bank")
        XCTAssertTrue(app.buttons["search.Checking Account"].waitForExistence(timeout: 5), "No search results")
        capture("05-Search")
    }

    /// Keeps a screenshot of the whole screen in the result bundle.
    @MainActor
    private func capture(_ name: String) {
        // Let animations and the keyboard settle.
        Thread.sleep(forTimeInterval: 1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
