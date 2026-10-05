import XCTest

/// End-to-end flows through the real UI on a simulator. Each test starts
/// from an empty library (-UITestReset) and creates its own database with
/// a cheap key derivation (-UITest), so tests don't depend on each other
/// or on files on the device.
final class KeePassIOUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app from an empty library.
    @MainActor
    private func launch() -> AppDriver {
        let app = XCUIApplication()
        app.launchArguments = ["-UITest", "-UITestReset"]
        app.launch()
        return AppDriver(app: app, test: self)
    }

    @MainActor
    func testLaunchShowsEmptyLibrary() throws {
        let app = launch().app
        XCTAssertTrue(app.staticTexts["No Databases"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.open"].exists)
        XCTAssertTrue(app.buttons["library.new"].exists)
    }

    @MainActor
    func testCreateAddSaveLockUnlockSearchAndReveal() throws {
        let driver = launch()
        let app = driver.app
        driver.createDatabase(named: "Personal")

        driver.addEntry(
            title: "Mail",
            userName: "alice@example.com",
            password: "hunter2-secret",
            url: "mail.example.com"
        )
        XCTAssertTrue(app.buttons["entry.Mail"].waitForExistence(timeout: 5))

        driver.save()
        driver.lock()

        // Wrong password first.
        driver.unlock(with: "not the password")
        XCTAssertTrue(app.staticTexts["unlock.error"].waitForExistence(timeout: 10))

        driver.unlock(with: AppDriver.password)
        XCTAssertTrue(app.buttons["entry.Mail"].waitForExistence(timeout: 10))

        // Search across the database.
        let search = app.textFields["group.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("alic")
        let hit = app.buttons["search.Mail"]
        XCTAssertTrue(hit.waitForExistence(timeout: 5))
        hit.tap()

        // The password is hidden until revealed. (Text inside a button is
        // part of the button's accessibility label.)
        let passwordRow = app.buttons["field.Password"]
        XCTAssertTrue(passwordRow.waitForExistence(timeout: 5))
        XCTAssertFalse(passwordRow.label.contains("hunter2-secret"))
        app.buttons["field.Password.reveal"].tap()
        let revealed = NSPredicate(format: "label CONTAINS %@", "hunter2-secret")
        expectation(for: revealed, evaluatedWith: passwordRow)
        waitForExpectations(timeout: 5)

        // Copying shows a confirmation.
        passwordRow.tap()
        XCTAssertTrue(app.staticTexts["entry.copied"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testGeneratedPasswordIsUsedAndEditKeepsHistory() throws {
        let driver = launch()
        let app = driver.app
        driver.createDatabase(named: "Generated")
        driver.openNewEntryForm()

        app.textFields["editor.title"].tap()
        app.textFields["editor.title"].typeText("Bank")
        app.buttons["editor.generate"].tap()
        let generated = app.staticTexts["generator.value"]
        XCTAssertTrue(generated.waitForExistence(timeout: 5))
        let generatedPassword = generated.label
        XCTAssertGreaterThanOrEqual(generatedPassword.count, 8)
        app.buttons["generator.use"].tap()
        XCTAssertEqual(app.textFields["editor.password"].value as? String, generatedPassword)
        app.buttons["editor.done"].tap()

        // Edit the entry: change the user name.
        app.buttons["entry.Bank"].tap()
        app.buttons["entry.edit"].tap()
        let userName = app.textFields["editor.userName"]
        XCTAssertTrue(userName.waitForExistence(timeout: 5))
        userName.tap()
        userName.typeText("bob")
        app.buttons["editor.done"].tap()
        XCTAssertTrue(app.buttons["History (1)"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDatabaseSurvivesRelaunch() throws {
        let driver = launch()
        let app = driver.app
        driver.createDatabase(named: "Persistent")
        driver.addEntry(title: "Router", userName: "admin", password: "router-pass", url: "")
        driver.save()

        // Relaunch without resetting: the library and file are still there.
        app.terminate()
        app.launchArguments = ["-UITest"]
        app.launch()
        let row = app.buttons["library.database.Persistent"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        driver.unlock(with: AppDriver.password)
        XCTAssertTrue(app.buttons["entry.Router"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLongPressMenusRenameDatabaseAndCopyPassword() throws {
        let driver = launch()
        let app = driver.app
        driver.createDatabase(named: "Database")
        driver.addEntry(title: "Bank", userName: "carol", password: "bank-pass", url: "")

        // Long-pressing an entry offers to copy its password.
        app.buttons["entry.Bank"].press(forDuration: 1)
        let copyPassword = app.buttons["entryMenu.copyPassword"]
        XCTAssertTrue(copyPassword.waitForExistence(timeout: 5), "The entry's long-press menu didn't appear")
        copyPassword.tap()

        driver.save()
        driver.goBack()

        // Long-pressing a database offers a rename; the alias replaces the
        // file name in the library.
        let row = app.buttons["library.database.Database"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Didn't get back to the library")
        row.press(forDuration: 1)
        let rename = app.buttons["library.rename"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "The database's long-press menu didn't appear")
        rename.tap()
        let field = app.textFields["library.rename.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The rename alert didn't appear")
        field.tap()
        field.typeText("Default")
        app.buttons["library.rename.confirm"].tap()
        XCTAssertTrue(
            app.buttons["library.database.Default"].waitForExistence(timeout: 5),
            "The alias didn't replace the file name in the library"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}

/// The steps the tests are made of, driving the app through the
/// accessibility identifiers set in the views.
@MainActor
struct AppDriver {
    static let password = "correct horse battery"
    let app: XCUIApplication
    let test: XCTestCase

    func createDatabase(named name: String) {
        let newButton = app.buttons["library.new"]
        XCTAssertTrue(newButton.waitForExistence(timeout: 5))
        newButton.tap()

        let nameField = app.textFields["newDatabase.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.clearText()
        nameField.typeText(name)
        app.secureTextFields["newDatabase.password"].tap()
        app.secureTextFields["newDatabase.password"].typeText(Self.password)
        app.secureTextFields["newDatabase.confirm"].tap()
        app.secureTextFields["newDatabase.confirm"].typeText(Self.password)
        app.buttons["newDatabase.create"].tap()

        // Creating opens the new, unlocked database.
        XCTAssertTrue(app.buttons["group.add"].waitForExistence(timeout: 15))
    }

    func openNewEntryForm() {
        app.buttons["group.add"].tap()
        let newEntry = app.buttons["group.newEntry"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 5))
    }

    func addEntry(title: String, userName: String, password: String, url: String) {
        openNewEntryForm()
        app.textFields["editor.title"].tap()
        app.textFields["editor.title"].typeText(title)
        app.textFields["editor.userName"].tap()
        app.textFields["editor.userName"].typeText(userName)
        let passwordField = app.textFields["editor.password"]
        passwordField.tap()
        passwordField.typeText(password)
        if !url.isEmpty {
            app.textFields["editor.url"].tap()
            app.textFields["editor.url"].typeText(url)
        }
        app.buttons["editor.done"].tap()
        XCTAssertTrue(app.buttons["entry.\(title)"].waitForExistence(timeout: 5))
    }

    func save() {
        let saveButton = app.buttons["database.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
        // The button is disabled once there's nothing left to save.
        let saved = NSPredicate(format: "isEnabled == false")
        test.expectation(for: saved, evaluatedWith: saveButton)
        test.waitForExpectations(timeout: 15)
    }

    /// Taps the navigation bar's back button. On iOS 26 it isn't reliably
    /// the bar's first button, so it's found by its system identifier or
    /// the previous screen's title first.
    func goBack() {
        let bar = app.navigationBars.firstMatch
        for candidate in [bar.buttons["BackButton"], bar.buttons["KeePassIO"]] where candidate.exists {
            candidate.tap()
            return
        }
        bar.buttons.element(boundBy: 0).tap()
    }

    func lock() {
        app.buttons["database.lock"].tap()
        XCTAssertTrue(app.secureTextFields["unlock.password"].waitForExistence(timeout: 5))
    }

    func unlock(with password: String) {
        let field = app.secureTextFields["unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.clearText()
        field.typeText(password)
        app.buttons["unlock.submit"].tap()
    }
}

@MainActor
extension XCUIElement {
    /// Deletes any text already in a text field.
    func clearText() {
        guard let current = value as? String, !current.isEmpty, current != placeholderValue else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    }
}
