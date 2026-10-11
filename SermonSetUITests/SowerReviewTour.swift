import XCTest

/// Walks every community screen in one look and attaches screenshots for design review.
/// Skipped unless `SOWER_SERVER` (a seeded local server) and `SOWER_REVIEW_LOOK` are set.
@MainActor
final class SowerReviewTour: XCTestCase {
    private var app: XCUIApplication!
    private var look = "riso"

    override func setUp() async throws {
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "\(name)-\(look)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    @discardableResult
    private func tap(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    /// The navigation back button; iOS 26 doesn't always expose it under navigationBars.
    private func goBack() {
        let back = app.buttons["BackButton"]
        if back.waitForExistence(timeout: 2) { back.tap(); return }
        let labelled = app.buttons.matching(NSPredicate(format: "label IN %@", ["Back", "Settings"])).firstMatch
        if labelled.exists { labelled.tap(); return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
    }

    private func scrollTo(_ element: XCUIElement, max: Int = 8) {
        var count = 0
        while !element.isHittable && count < max { app.swipeUp(); count += 1 }
    }

    func testTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let server = env["SOWER_SERVER"], let look = env["SOWER_REVIEW_LOOK"] else { throw XCTSkip("Set SOWER_SERVER and SOWER_REVIEW_LOOK.") }
        self.look = look
        app = XCUIApplication()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SowerTour-\(UUID().uuidString)").path
        app.launchArguments = ["-SermonSetUITest", "-SermonSetSimulatedCapture", "-SermonSetSkipOnboarding", "-SermonSetPreviewData", "-SermonSetLook", look, "-SermonSetUITestDirectory", dir, "-SermonSetServer", server]
        app.launch()

        // Join from Settings.
        tap(app.buttons["Settings"].firstMatch)
        scrollTo(app.buttons["settings.join"])
        shot("10-settings-join")
        tap(app.buttons["settings.join"])
        shot("11-join-sheet")
        let name = app.textFields.firstMatch
        if name.waitForExistence(timeout: 5) { name.tap(); name.typeText("Ruth") }
        tap(app.buttons["join.create"])
        _ = element(containing: "You’re in").waitForExistence(timeout: 20)
        shot("12-joined")
        tap(app.buttons["Done"].firstMatch)
        tap(app.buttons["settings.account"])
        shot("13-account")
        app.swipeUp()
        shot("14-account-recovery")
        tap(app.buttons["Show a code"])
        app.swipeUp()
        shot("15-account-link-browser")
        goBack()
        scrollTo(element(containing: "Back up to Files"))
        shot("16-settings-backup")
        tap(app.buttons["Done"].firstMatch)

        // Discover, a community sermon, keep, listen.
        tap(app.buttons["Discover"].firstMatch)
        _ = element(containing: "Recently shared").waitForExistence(timeout: 20)
        shot("20-discover")
        app.swipeUp()
        shot("21-discover-shared")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Fictional Sample Fellowship")).firstMatch
        tap(tile)
        shot("22-community-sermon")
        tap(app.buttons["community.keep"], timeout: 15)
        _ = app.buttons["Open in library"].waitForExistence(timeout: 20)
        app.swipeUp()
        shot("23-community-kept")
        tap(app.buttons["community.play"])
        sleep(3)
        shot("24-community-playing")
        tap(app.buttons["Close"].firstMatch)
        shot("25-community-miniplayer")

        // Trading.
        tap(app.buttons["Collection"].firstMatch)
        let binder = app.buttons["Binder"].firstMatch
        if binder.waitForExistence(timeout: 3) { binder.tap() }
        app.swipeUp()
        shot("30-collection-trading")
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", " card, ", "Community edition")).firstMatch
        tap(card)
        shot("31-card-community")
        tap(app.buttons["card.trade"], timeout: 15)
        shot("32-offer-compose")
        tap(app.buttons["offer.create"])
        _ = element(containing: "QR code for the").waitForExistence(timeout: 20)
        shot("33-offer-qr")
        tap(app.buttons["Link"].firstMatch)
        shot("34-offer-link")
        tap(app.buttons["Cancel offer"])
        sleep(2)
        tap(app.buttons["Done"].firstMatch)
        tap(app.buttons["Journey"].firstMatch)
        shot("35-journey")
        tap(app.buttons["Done"].firstMatch)
        tap(app.buttons["Close"].firstMatch)
        tap(app.buttons["collection.receive"])
        shot("36-receive")
        tap(app.buttons["Cancel"].firstMatch)

        // Inbox.
        tap(app.buttons["toolbar.inbox"])
        shot("40-inbox")
        tap(app.buttons["Done"].firstMatch)

        // Record with a service code, then share the recording.
        tap(app.buttons["Library"].firstMatch)
        tap(app.buttons["Record a sermon"].firstMatch)
        shot("50-record-setup")
        tap(app.buttons["record.scanService"])
        shot("51-service-scanner")
        tap(app.buttons["Cancel"].firstMatch)
        tap(app.buttons["Recording is welcome at this service"].firstMatch)
        tap(app.buttons["Start recording"])
        sleep(3)
        tap(app.buttons["Stop"])
        tap(app.buttons["Stop and save"])
        tap(app.buttons["Open sermon"], timeout: 20)
        let share = app.buttons["sermon.share"]
        scrollTo(share)
        shot("52-share-section")
        tap(share)
        shot("53-publish-what")
        tap(app.buttons["publish.next"])
        shot("54-publish-church")
        if tap(app.buttons["publish.addDetails"]) {
            for (field, text) in [("Title", "The Seed and the Soil"), ("Preacher", "Grace Ellison"), ("Scripture passage", "Mark 4:1–20")] {
                let input = app.textFields.matching(NSPredicate(format: "placeholderValue BEGINSWITH %@", field)).firstMatch
                if tap(input) { input.typeText(text) }
            }
            let kind = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Kind")).firstMatch
            scrollTo(kind, max: 3)
            tap(kind)
            tap(app.buttons["Hope"].firstMatch)
            tap(app.buttons["Save"].firstMatch)
            shot("54b-publish-details-added")
        }
        tap(app.buttons["publish.next"])
        shot("55-publish-check")
        for title in ["music and songs", "prayer requests", "children", "private conversations"] {
            let box = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Checked for \(title)")).firstMatch
            scrollTo(box, max: 3)
            tap(box)
        }
        tap(app.buttons["publish.next"])
        shot("56-publish-confirm")
        tap(app.buttons["publish.send"])
        sleep(4)
        shot("57-publish-status")
    }
}
