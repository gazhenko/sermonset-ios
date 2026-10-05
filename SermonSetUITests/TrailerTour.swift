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
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SERMONSET_TRAILER"] == "1", "Trailer filming only")
    }

    private func mark(_ scene: String, _ edge: String) {
        print(String(format: "TRAILER-MARK %@ %@ %.3f", scene, edge, Date().timeIntervalSince1970))
    }

    /// `pinned: false` seeds the look instead of pinning it, so the look picker can change it live.
    private func open(_ look: String, _ args: [String] = [], pinned: Bool = true) {
        app?.terminate()
        app = XCUIApplication()
        let lookArgs = pinned ? ["-SermonSetLook", look] : ["-SermonSetInitialLook", look]
        app.launchArguments = ["-SermonSetPreviewData", "-SermonSetSimulatedCapture"] + lookArgs + args
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

    func testTour() {
        // Riso: the library, then into a sermon and press play.
        open("riso")
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
        open("rubric", ["-SermonSetScreen", "recording"])
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
        open("lumen", ["-SermonSetScreen", "card"])
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

        // Riso: the free Sunday Pack.
        open("riso", ["-SermonSetScreen", "pack"])
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
        open("rubric", ["-SermonSetScreen", "atlas"])
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

        // Settings: four looks, one app — the whole UI restyles live.
        open("vespers", ["-SermonSetScreen", "settings"], pinned: false)
        scene("looks", settle: 1.8) {
            for name in ["Riso", "Rubric", "Lumen", "Vespers"] {
                let tile = button("label BEGINSWITH '\(name) look'")
                if tile.waitForExistence(timeout: 3) { tile.tap() }
                pause(1.5)
            }
        }
        app.terminate()
    }
}
