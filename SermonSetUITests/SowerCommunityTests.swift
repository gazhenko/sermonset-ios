import XCTest

/// Community journeys against a local server. Skipped unless `SOWER_SERVER` is set, e.g.
/// `TEST_RUNNER_SOWER_SERVER=http://127.0.0.1:8787 xcodebuild test …` with a seeded `wrangler dev`.
@MainActor
final class SowerCommunityTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private var server: String? { ProcessInfo.processInfo.environment["SOWER_SERVER"] }

    private func launch() throws {
        guard let server else { throw XCTSkip("Set SOWER_SERVER to run community journeys.") }
        app = XCUIApplication()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SowerCommunity-\(UUID().uuidString)").path
        app.launchArguments = ["-SermonSetUITest", "-SermonSetSimulatedCapture", "-SermonSetSkipOnboarding", "-SermonSetLook", "riso", "-SermonSetUITestDirectory", dir, "-SermonSetServer", server]
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    private func joinCommunity() {
        tap(app.buttons["Settings"].firstMatch)
        tap(app.buttons["settings.join"])
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test Listener")
        tap(app.buttons["join.create"])
        XCTAssertTrue(element(containing: "You’re in").waitForExistence(timeout: 20), "Account created against the server")
        shot("community-01-joined")
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(app.buttons["settings.account"].waitForExistence(timeout: 5), "Settings shows the account")
        tap(app.buttons["Done"].firstMatch)
    }

    func testJoinKeepAndOfferACard() throws {
        try launch()
        joinCommunity()

        tap(app.buttons["Discover"].firstMatch)
        XCTAssertTrue(element(containing: "Recently shared").waitForExistence(timeout: 20), "Discover lists shared sermons")
        shot("community-02-discover")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fictional Sample Fellowship")).firstMatch
        tap(tile)
        tap(app.buttons["community.keep"], timeout: 15)
        XCTAssertTrue(app.buttons["Open in library"].waitForExistence(timeout: 20), "Keeping adds it to the library")
        shot("community-03-kept")
        tap(app.buttons["Close"].firstMatch)

        tap(app.buttons["Collection"].firstMatch)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " card, ")).firstMatch
        tap(card)
        tap(app.buttons["card.trade"], timeout: 15)
        tap(app.buttons["offer.create"])
        XCTAssertTrue(element(containing: "QR code for the").waitForExistence(timeout: 20), "A gift offer shows its QR code")
        shot("community-04-offer")
        tap(app.buttons["Cancel offer"])
        XCTAssertTrue(element(containing: "Offer cancelled").waitForExistence(timeout: 15), "Cancelling leaves the card in the binder")
    }

    func testShareDetailsOfARecording() throws {
        try launch()
        joinCommunity()
        tap(app.buttons["Library"].firstMatch)
        tap(app.buttons["Record a sermon"].firstMatch)
        tap(app.buttons["Recording is welcome at this service"].firstMatch)
        tap(app.buttons["Start recording"])
        sleep(3)
        tap(app.buttons["Stop"])
        tap(app.buttons["Stop and save"])
        tap(app.buttons["Open sermon"], timeout: 20)

        let share = app.buttons["sermon.share"]
        for _ in 0..<8 where !share.isHittable { app.swipeUp() }
        tap(share)
        tap(app.buttons["publish.next"])
        // A card needs a title, preacher, passage, and kind; nothing is filled in for you.
        XCTAssertFalse(app.buttons["publish.next"].isEnabled, "Sharing waits for the missing details")
        tap(app.buttons["publish.addDetails"])
        for (field, text) in [("Title", "The Seed and the Soil"), ("Preacher", "Test Preacher"), ("Scripture passage", "Mark 4:1–20")] {
            let input = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", field)).firstMatch
            tap(input)
            input.typeText(text)
        }
        let kind = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kind")).firstMatch
        XCTAssertTrue(kind.waitForExistence(timeout: 5))
        for _ in 0..<3 where !kind.isHittable { app.swipeUp() }
        kind.tap()
        tap(app.buttons["Hope"].firstMatch)
        tap(app.buttons["Save"].firstMatch)
        tap(app.buttons["publish.next"])
        for title in ["music and songs", "prayer requests", "children", "private conversations"] {
            let box = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Checked for \(title)")).firstMatch
            XCTAssertTrue(box.waitForExistence(timeout: 5))
            for _ in 0..<4 where !box.isHittable { app.swipeUp() }
            box.tap()
        }
        tap(app.buttons["publish.next"])
        shot("community-05-confirm")
        tap(app.buttons["publish.send"])
        XCTAssertTrue(element(containing: "Waiting for").waitForExistence(timeout: 30), "The share waits for permission before going public")
        shot("community-06-pending")
    }
}
