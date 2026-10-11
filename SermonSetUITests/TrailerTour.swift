import XCTest

/// Films the trailer: a scripted tour of the real app, one look per scene. Skipped in normal test
/// runs; `tools/trailer/record.sh` enables it with TEST_RUNNER_SERMONSET_TRAILER=1 while the
/// Simulator screen is being recorded. Each scene logs `TRAILER-MARK <scene> <start|end> <epoch>`
/// so the editor can cut the recording precisely.
@MainActor
final class TrailerTour: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["SERMONSET_TRAILER"] == "1" || env["SERMONSET_TRAILER_SETUP"] == "1", "Trailer filming only")
    }

    /// A seeded local server for the community scenes (`SOWER_SERVER`), if one is running.
    private var server: [String] {
        ProcessInfo.processInfo.environment["SOWER_SERVER"].map { ["-SermonSetServer", $0] } ?? []
    }

    /// The community scenes share one persistent library (preview data starts fresh on every launch).
    private var communityData: [String] {
        let dir = ProcessInfo.processInfo.environment["SOWER_TRAILER_DIR"]
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("SowerTrailer").path
        return ["-SermonSetUITest", "-SermonSetUITestDirectory", dir, "-SermonSetSkipOnboarding", "-SermonSetSimulatedCapture"]
    }

    private func openCommunity(_ look: String, _ args: [String] = []) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = communityData + ["-SermonSetLook", look] + server + args
        app.launch()
    }

    /// Run once before filming: joins the community and keeps two shared sermons, so the tour's
    /// community scenes have cards to trade. Uses the app's normal data, which the tour reuses.
    func testPrepareCommunity() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SERMONSET_TRAILER_SETUP"] == "1", "Trailer setup only")
        openCommunity("sower")
        app.buttons["Settings"].firstMatch.tap()
        let join = app.buttons["settings.join"]
        for _ in 0..<6 where !join.isHittable && !app.buttons["settings.account"].exists { app.swipeUp() }
        if join.exists {
            join.tap()
            let name = app.textFields.firstMatch
            if name.waitForExistence(timeout: 5) { name.tap(); name.typeText("Ruth") }
            app.buttons["join.create"].tap()
            _ = app.staticTexts["You’re in"].waitForExistence(timeout: 20)
            app.buttons["Done"].firstMatch.tap()
        }
        app.buttons["Done"].firstMatch.tap()
        app.buttons["Discover"].firstMatch.tap()
        for index in 0..<2 {
            let tiles = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)", "Fictional Sample Fellowship", "In your library"))
            guard tiles.firstMatch.waitForExistence(timeout: 20) else { break }
            tiles.element(boundBy: 0).tap()
            let keep = app.buttons["community.keep"]
            if keep.waitForExistence(timeout: 15) { keep.tap() }
            _ = app.buttons["Open in library"].waitForExistence(timeout: 20)
            app.buttons["Close"].firstMatch.tap()
            pause(Double(index))
        }
    }

    private func mark(_ scene: String, _ edge: String) {
        print(String(format: "TRAILER-MARK %@ %@ %.3f", scene, edge, Date().timeIntervalSince1970))
    }

    /// `pinned: false` seeds the look instead of pinning it, so the look picker can change it live.
    private func open(_ look: String, _ args: [String] = [], pinned: Bool = true) {
        app?.terminate()
        app = XCUIApplication()
        let lookArgs = pinned ? ["-SermonSetLook", look] : ["-SermonSetInitialLook", look]
        app.launchArguments = ["-SermonSetPreviewData", "-SermonSetSimulatedCapture"] + lookArgs + server + args
        app.launch()
    }

    private func pause(_ seconds: Double) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private func button(_ predicate: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: predicate)).firstMatch
    }

    private func scene(_ name: String, settle: Double = 1.2, _ body: () -> Void) {
        pause(settle)
        mark(name, "start")
        body()
        mark(name, "end")
    }

    func testTour() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SERMONSET_TRAILER"] == "1", "Trailer filming only")
        // Riso: the library, then into a sermon and press play.
        open("sower")
        scene("library") {
            pause(1.6)
            app.swipeUp(velocity: .slow)
            pause(0.8)
            app.swipeDown(velocity: .slow)
            pause(0.6)
            let row = button("label BEGINSWITH 'Breakfast on the Shore,'")
            if row.waitForExistence(timeout: 4) { row.tap() }
            pause(1.6)
        }
        scene("play", settle: 0.2) {
            let play = app.buttons["player.play"]
            if play.waitForExistence(timeout: 4) { play.tap() }
            pause(2.6)
            let mark = app.buttons["Mark this moment"].firstMatch
            if mark.exists { mark.tap() }
            pause(2.2)
        }

        // Rubric: a live recording, marking the moment it lands.
        open("sower", ["-SermonSetScreen", "recording"])
        scene("record", settle: 2.0) {
            pause(1.4)
            let mark = app.buttons["Mark this moment"].firstMatch
            if mark.waitForExistence(timeout: 4) {
                mark.tap(); pause(1.8)
                mark.tap(); pause(1.6)
            }
            pause(1.2)
        }

        // Vespers: takeaways linked to the exact audio.
        open("vespers", ["-SermonSetScreen", "sermon", "-SermonSetScroll", "takeaways"])
        scene("takeaways", settle: 1.8) {
            pause(1.4)
            let hear = button("label BEGINSWITH 'Hear the source'")
            if hear.waitForExistence(timeout: 4) { hear.tap() }
            pause(5.0)
        }

        // Lumen: the card up close — tilt, flip, tilt.
        open("sower", ["-SermonSetScreen", "card"])
        scene("card", settle: 1.8) {
            let card = app.descendants(matching: .any)["card.stage"]
            guard card.waitForExistence(timeout: 4) else { return }
            let center = card.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.35)),
                         withVelocity: .slow, thenHoldForDuration: 0.5)
            pause(0.9)
            center.press(forDuration: 0.05, thenDragTo: card.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)),
                         withVelocity: .slow, thenHoldForDuration: 0.5)
            pause(0.9)
            card.tap()
            pause(1.8)
            card.tap()
            pause(1.4)
        }

        // Vespers: community sermons other churches shared, kept in a tap.
        openCommunity("sower", ["-SermonSetScreen", "discover"])
        scene("discover", settle: 2.4) {
            pause(1.2)
            app.swipeUp(velocity: .slow)
            pause(1.0)
            let tile = button("label CONTAINS[c] 'Fictional Sample Fellowship' AND NOT (label CONTAINS[c] 'In your library')")
            if tile.waitForExistence(timeout: 6) { tile.tap() }
            pause(1.8)
            let keep = app.buttons["community.keep"]
            if keep.waitForExistence(timeout: 6) { keep.tap() }
            pause(2.4)
        }

        // Riso: give a card — the offer as a QR code.
        openCommunity("sower", ["-SermonSetScreen", "binder"])
        scene("trade", settle: 2.0) {
            let card = button("label CONTAINS 'Community edition'")
            if card.waitForExistence(timeout: 6) { card.tap() }
            pause(1.6)
            let trade = app.buttons["card.trade"]
            if trade.waitForExistence(timeout: 6) { trade.tap() }
            pause(1.4)
            let create = app.buttons["offer.create"]
            if create.waitForExistence(timeout: 4) { create.tap() }
            let qr = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'QR code for the'")).firstMatch
            _ = qr.waitForExistence(timeout: 12)
            pause(3.6)
            let cancel = app.buttons["Cancel offer"]
            if cancel.exists { cancel.tap() }
            pause(0.6)
        }

        // Riso: the free Sunday Pack.
        open("sower", ["-SermonSetScreen", "pack"])
        scene("pack", settle: 1.6) {
            pause(1.0)
            app.buttons["Tear it open"].tap()
            pause(1.4)
            for _ in 0..<2 {
                let reveal = app.buttons["Reveal"]
                if reveal.waitForExistence(timeout: 3) { reveal.tap() }
                pause(1.3)
                let next = app.buttons["Next card"]
                if next.exists { next.tap() }
                pause(0.7)
            }
            let all = app.buttons["Reveal all"]
            if all.exists { all.tap() }
            pause(2.4)
        }

        // Rubric: where the messages were preached.
        open("sower", ["-SermonSetScreen", "atlas"])
        scene("atlas", settle: 4.0) {
            pause(1.5)
            // Scroll from the list below the map so the gesture doesn't pan the map.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
            pause(0.8)
            let place = button("label BEGINSWITH 'Portland'")
            if place.exists { place.tap() }
            pause(2.0)
        }

        // Settings: five looks, one app — the whole UI restyles live, ending on SOWER.
        open("vespers", ["-SermonSetScreen", "settings"], pinned: false)
        scene("looks", settle: 1.8) {
            for name in ["Riso", "Rubric", "Lumen", "Vespers", "SOWER"] {
                let tile = button("label BEGINSWITH '\(name) look'")
                if tile.waitForExistence(timeout: 3) { tile.tap() }
                pause(1.5)
            }
        }
        app.terminate()
    }
}
