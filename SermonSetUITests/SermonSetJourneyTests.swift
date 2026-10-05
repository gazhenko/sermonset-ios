import XCTest

/// End-to-end journeys through the real app on Simulator. Capture uses the simulated engine,
/// so these prove the UI flow and persistence, not microphone quality (that needs a real iPhone).
@MainActor
final class SermonSetJourneyTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(look: String = "riso", fresh: Bool = true, extra: [String] = []) {
        app = XCUIApplication()
        var args = ["-SermonSetUITest", "-SermonSetSimulatedCapture", "-SermonSetSkipOnboarding", "-SermonSetLook", look]
        if fresh {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SermonSetUITest-\(UUID().uuidString)").path
            args += ["-SermonSetUITestDirectory", dir]
        }
        app.launchArguments = args + extra
        app.launch()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Any element whose accessibility label contains the text (screen titles and rows combine their children).
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return condition()
    }

    private func tap(_ element: XCUIElement, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    func testRecordMarkNoteStopAndRevisit() {
        launch(look: "vespers")
        XCTAssertTrue(element(containing: "Start with a sermon").waitForExistence(timeout: 8), "New users see an honest empty state")
        shot("01-empty-library")

        tap(app.buttons["Record a sermon"].firstMatch)
        XCTAssertFalse(app.buttons["Start recording"].isEnabled, "Recording waits for the consent check")
        tap(app.buttons["Recording is welcome at this service"].firstMatch)
        shot("02-ready-to-record")
        tap(app.buttons["Start recording"])

        let mark = app.buttons["Mark this moment"]
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 8) { mark.isEnabled }, "Mark becomes available once recording starts")
        sleep(2)
        mark.tap()
        sleep(1)
        mark.tap()
        tap(app.buttons["Write a note"])
        let note = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 4))
        note.typeText("The waiting is the room")
        tap(app.buttons["Save note"])
        sleep(1)
        shot("03-recording")

        tap(app.buttons["Stop"])
        tap(app.buttons["Stop and save"])
        XCTAssertTrue(element(containing: "Saved to your library").waitForExistence(timeout: 15))
        shot("04-saved")
        tap(app.buttons["Open sermon"])

        XCTAssertTrue(element(containing: "Untitled sermon").waitForExistence(timeout: 8))
        app.swipeUp()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Moment at'")).count >= 2, "Both marked moments are saved")
        shot("05-revisit")

        // Relaunch: the recording, moments, and note persist on disk.
        let dirIndex = app.launchArguments.firstIndex(of: "-SermonSetUITestDirectory")!
        let dir = app.launchArguments[dirIndex + 1]
        app.terminate()
        launch(look: "vespers", fresh: false, extra: ["-SermonSetUITestDirectory", dir])
        XCTAssertTrue(element(containing: "Untitled sermon").waitForExistence(timeout: 8), "Library survives relaunch")
        shot("06-after-relaunch")
    }

    func testSamplesPackBinderAndTradePreviewKeepsTheSermon() {
        launch(look: "riso")
        tap(app.buttons["Explore with sample sermons"])
        XCTAssertTrue(element(containing: "2 sermons, kept for good").waitForExistence(timeout: 8))

        tap(app.buttons["Discover"])
        tap(app.buttons["Open pack"])
        tap(app.buttons["Tear it open"])
        tap(app.buttons["Reveal"])
        shot("10-pack-reveal")
        tap(app.buttons["Reveal all"])
        let keep = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Keep all'")).firstMatch
        tap(keep)
        XCTAssertTrue(element(containing: "Added to your library and binder").waitForExistence(timeout: 8))
        shot("11-pack-kept")
        tap(app.buttons["Go to Library"])

        let libraryCount = element(containing: "kept for good")
        XCTAssertTrue(libraryCount.waitForExistence(timeout: 8))
        let before = libraryCount.label

        tap(app.buttons["Collection"])
        let firstCard = app.buttons.matching(NSPredicate(format: "label CONTAINS ' card, '")).firstMatch
        tap(firstCard)
        tap(app.buttons["Practice a trade"])
        shot("12-trade-preview")
        tap(app.buttons["Remove card from binder"])
        XCTAssertTrue(element(containing: "The card left your binder").waitForExistence(timeout: 6))
        shot("13-after-trade")
        tap(app.buttons["Close"])

        tap(app.buttons["Library"])
        XCTAssertEqual(libraryCount.label, before, "Trading a card never removes a sermon from the library")
    }

    func testOnboardingChoosesALookAndHandsOffToTheRecorder() {
        launch(look: "lumen", extra: ["-SermonSetScreen", "onboarding"])
        tap(app.buttons["Continue"])
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Vespers look'")).firstMatch)
        shot("40-choose-look")
        tap(app.buttons["Continue"])
        tap(app.buttons["onboarding.record"])
        XCTAssertTrue(app.buttons["Recording is welcome at this service"].waitForExistence(timeout: 8),
                      "Choosing Record on the last onboarding step opens the recorder")
        shot("41-recorder-after-onboarding")
    }

    func testKilledRecordingIsRecoverableAfterRelaunch() {
        launch(look: "rubric")
        tap(app.buttons["Record a sermon"].firstMatch)
        tap(app.buttons["Recording is welcome at this service"].firstMatch)
        tap(app.buttons["Start recording"])
        let mark = app.buttons["Mark this moment"]
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil(timeout: 8) { mark.isEnabled })
        sleep(4)
        mark.tap()
        sleep(32) // past the first durable segment boundary

        // Simulate the app being killed mid-sermon.
        let dirIndex = app.launchArguments.firstIndex(of: "-SermonSetUITestDirectory")!
        let dir = app.launchArguments[dirIndex + 1]
        app.terminate()
        launch(look: "rubric", fresh: false, extra: ["-SermonSetUITestDirectory", dir])

        XCTAssertTrue(element(containing: "A recording was interrupted").waitForExistence(timeout: 10), "Relaunch offers recovery")
        shot("30-recovery-offer")
        tap(app.buttons["Keep recording"])
        XCTAssertTrue(element(containing: "Untitled sermon").waitForExistence(timeout: 10), "Recovered audio becomes a sermon")
        shot("31-recovered")
    }

    func testEveryLookRendersTheLibrary() {
        for look in ["riso", "rubric", "vespers", "lumen"] {
            launch(look: look, extra: ["-SermonSetPreviewData"])
            XCTAssertTrue(element(containing: "kept for good").waitForExistence(timeout: 8))
            shot("20-library-\(look)")
            app.terminate()
        }
    }
}
