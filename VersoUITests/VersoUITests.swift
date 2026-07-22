//
//  VersoUITests.swift
//  VersoUITests
//
//  Created by Leo Chen on 2026/7/22.
//

import XCTest

final class VersoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLaunchShowsWorkspaceShell() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-ApplePersistenceIgnoreState", "YES",
            "-workspace.last.security-scoped-bookmark", ""
        ]
        app.launch()

        if !app.windows.firstMatch.waitForExistence(timeout: 2) {
            app.typeKey("n", modifierFlags: .command)
        }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["workspace.welcome"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["workspace.create"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["workspace.open"].exists
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
