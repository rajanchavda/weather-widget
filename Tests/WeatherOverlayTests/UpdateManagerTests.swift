import XCTest
@testable import WeatherOverlayCore

@MainActor
final class UpdateManagerTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []
        URLProtocol.registerClass(URLProtocolMock.self)
    }

    override func tearDown() async throws {
        URLProtocol.unregisterClass(URLProtocolMock.self)
        URLProtocolMock.requestHandler = nil
        URLProtocolMock.responseDelay = 0
        URLProtocolMock.delayedURLs = []
        try await super.tearDown()
    }

    // MARK: - GitHub Release JSON Parsing

    func testLatestVersion_stripsLeadingV() {
        let json = #"{ "tag_name": "v1.1.0", "name": "v1.1.0", "body": "Bug fixes" }"#.data(using: .utf8)!
        XCTAssertEqual(UpdateManager.latestVersion(fromReleaseJSON: json), "1.1.0")
    }

    func testLatestVersion_withoutV() {
        let json = #"{ "tag_name": "1.2.0" }"#.data(using: .utf8)!
        XCTAssertEqual(UpdateManager.latestVersion(fromReleaseJSON: json), "1.2.0")
    }

    func testLatestVersion_keepsInnerV() {
        let json = #"{ "tag_name": "v2.0.0-preview" }"#.data(using: .utf8)!
        XCTAssertEqual(UpdateManager.latestVersion(fromReleaseJSON: json), "2.0.0-preview")
    }

    func testLatestVersion_missingTagOrInvalidJSON() {
        XCTAssertNil(UpdateManager.latestVersion(fromReleaseJSON: #"{ "message": "rate limited" }"#.data(using: .utf8)!))
        XCTAssertNil(UpdateManager.latestVersion(fromReleaseJSON: Data("not json".utf8)))
    }

    // MARK: - Version Comparison

    func testIsVersionNewer() {
        XCTAssertTrue(UpdateManager.isVersion("1.1.0", newerThan: "1.0.0"))
        XCTAssertTrue(UpdateManager.isVersion("1.0.10", newerThan: "1.0.9"))
        XCTAssertFalse(UpdateManager.isVersion("1.0.0", newerThan: "1.0.0"))
        XCTAssertFalse(UpdateManager.isVersion("1.0.0", newerThan: "1.1.0"))
    }

    // MARK: - Background Check

    func testBackgroundCheck_inAppBundle_callsGitHub() throws {
        let json = #"{ "tag_name": "v999.999.999" }"#.data(using: .utf8)!
        let requestExpectation = expectation(description: "GitHub API called")

        URLProtocolMock.requestHandler = { request in
            XCTAssertTrue((request.url?.absoluteString ?? "").contains("api.github.com"))
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let appDelegate = AppDelegate()
        appDelegate.updateManager.isAppBundle = true
        appDelegate.updateManager.performUpdateCheck(isUserInitiated: false)

        wait(for: [requestExpectation], timeout: 5.0)
    }

    func testBackgroundCheck_outsideAppBundle_makesNoRequest() throws {
        let requestExpectation = expectation(description: "GitHub API must not be called")
        requestExpectation.isInverted = true

        URLProtocolMock.requestHandler = { request in
            requestExpectation.fulfill()
            throw URLError(.notConnectedToInternet)
        }

        let appDelegate = AppDelegate()
        appDelegate.updateManager.isAppBundle = false
        appDelegate.updateManager.performUpdateCheck(isUserInitiated: false)

        wait(for: [requestExpectation], timeout: 0.5)
    }

    func testBackgroundCheck_networkError_flagsNothing() throws {
        let requestExpectation = expectation(description: "GitHub API called")

        URLProtocolMock.requestHandler = { request in
            requestExpectation.fulfill()
            throw URLError(.notConnectedToInternet)
        }

        let appDelegate = AppDelegate()
        appDelegate.updateManager.isAppBundle = true
        appDelegate.updateManager.performUpdateCheck(isUserInitiated: false)

        wait(for: [requestExpectation], timeout: 5.0)
        XCTAssertFalse(appDelegate.isUpdateReady)
    }

    // MARK: - Check Result Handling

    private func makeDelegateWithMenu() -> (AppDelegate, NSStatusItem) {
        let appDelegate = AppDelegate()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem
        appDelegate.menuBarManager.buildMenu(for: statusItem)
        return (appDelegate, statusItem)
    }

    private func updateMenuItem(in statusItem: NSStatusItem) -> NSMenuItem? {
        statusItem.menu?.items.first { $0.action == #selector(AppDelegate.checkForUpdates) }
    }

    func testBackgroundResult_newerVersion_flagsMenuWithoutInstalling() {
        let (appDelegate, statusItem) = makeDelegateWithMenu()
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        appDelegate.updateManager.handleCheckResult(latestVersion: "999.0.0", isUserInitiated: false)

        XCTAssertTrue(appDelegate.isUpdateReady)
        XCTAssertEqual(appDelegate.updateManager.availableVersion, "999.0.0")
        XCTAssertEqual(updateMenuItem(in: statusItem)?.title, "Update Available (v999.0.0)...")
        XCTAssertNotEqual(statusItem.button?.title, "🌤️ Updating...", "A background check must never start the upgrade")
    }

    func testBackgroundResult_sameOrOlderVersion_flagsNothing() {
        let (appDelegate, statusItem) = makeDelegateWithMenu()
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        appDelegate.updateManager.handleCheckResult(latestVersion: "0.0.1", isUserInitiated: false)

        XCTAssertFalse(appDelegate.isUpdateReady)
        XCTAssertNil(appDelegate.updateManager.availableVersion)
        XCTAssertEqual(updateMenuItem(in: statusItem)?.title, "Check for Updates")
    }

    func testBackgroundResult_failedCheck_flagsNothing() {
        let (appDelegate, statusItem) = makeDelegateWithMenu()
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        appDelegate.updateManager.handleCheckResult(latestVersion: nil, isUserInitiated: false)

        XCTAssertFalse(appDelegate.isUpdateReady)
        XCTAssertEqual(updateMenuItem(in: statusItem)?.title, "Check for Updates")
    }
}
