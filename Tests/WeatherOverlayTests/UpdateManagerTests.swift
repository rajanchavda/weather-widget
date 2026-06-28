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

    func testGitHubReleaseJSON_decoding() throws {
        let json = """
        {
          "tag_name": "v1.1.0",
          "name": "v1.1.0",
          "body": "Bug fixes and improvements"
        }
        """.data(using: .utf8)!

        let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let tag = parsed?["tag_name"] as? String
        let cleaned = tag?.replacingOccurrences(of: "v", with: "")

        XCTAssertEqual(cleaned, "1.1.0")
    }

    func testGitHubReleaseJSON_withoutV() throws {
        let json = """
        {
          "tag_name": "1.2.0",
          "name": "1.2.0"
        }
        """.data(using: .utf8)!

        let parsed = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        let tag = parsed?["tag_name"] as? String
        let cleaned = tag?.replacingOccurrences(of: "v", with: "")

        XCTAssertEqual(cleaned, "1.2.0")
    }

    // MARK: - Version Comparison

    func testVersionComparison_newerAvailable() {
        let result = "1.1.0".compare("1.0.0", options: .numeric)
        XCTAssertEqual(result, .orderedDescending)
    }

    func testVersionComparison_sameVersion() {
        let result = "1.0.0".compare("1.0.0", options: .numeric)
        XCTAssertEqual(result, .orderedSame)
    }

    func testVersionComparison_olderVersion() {
        let result = "1.0.0".compare("1.1.0", options: .numeric)
        XCTAssertEqual(result, .orderedAscending)
    }

    func testVersionComparison_multiDigit() {
        let result = "1.0.10".compare("1.0.0", options: .numeric)
        XCTAssertEqual(result, .orderedDescending)
    }

    func testVersionComparison_withoutVPrefix() {
        let result = "1.0.1".compare("1.0.0", options: .numeric)
        XCTAssertEqual(result, .orderedDescending)
    }

    // MARK: - Network Integration (with URLProtocolMock)

    func testPerformUpdateCheck_newerVersionAvailable() throws {
        let json = """
        { "tag_name": "v999.999.999", "name": "v999.999.999" }
        """.data(using: .utf8)!

        let requestExpectation = expectation(description: "GitHub API called")

        URLProtocolMock.requestHandler = { request in
            let urlString = request.url?.absoluteString ?? ""
            XCTAssertTrue(urlString.contains("api.github.com"))
            requestExpectation.fulfill()
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let appDelegate = TestAppDelegate()
        let updateManager = UpdateManager(appDelegate: appDelegate)

        updateManager.performUpdateCheck(isUserInitiated: false)

        wait(for: [requestExpectation], timeout: 5.0)
    }

    func testPerformUpdateCheck_networkError() throws {
        let requestExpectation = expectation(description: "GitHub API called")

        URLProtocolMock.requestHandler = { request in
            requestExpectation.fulfill()
            throw URLError(.notConnectedToInternet)
        }

        let appDelegate = TestAppDelegate()
        let updateManager = UpdateManager(appDelegate: appDelegate)

        updateManager.performUpdateCheck(isUserInitiated: false)

        wait(for: [requestExpectation], timeout: 5.0)
    }
}

@MainActor
private class TestAppDelegate: AppDelegate {
    override init() {}
}
