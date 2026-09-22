import XCTest
@testable import CodexUsage

final class RateLimitParserTests: XCTestCase {
    func testParsesRealisticResponseAndCalculatesRemaining() throws {
        let json = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":16,"windowDurationMins":300,"resetsAt":1760000000},"secondary":{"usedPercent":78,"windowDurationMins":10080,"resetsAt":1760100000}}}}"#
        let response = try XCTUnwrap(RateLimitParser.parseResponseLine(Data(json.utf8)))
        XCTAssertEqual(response.rateLimits.primary?.remainingPercent, 84)
        XCTAssertEqual(response.rateLimits.secondary?.remainingPercent, 22)
    }

    func testRemainingIsClamped() {
        XCTAssertEqual(RateLimitWindow(usedPercent: -20, windowDurationMins: nil, resetsAt: nil).remainingPercent, 100)
        XCTAssertEqual(RateLimitWindow(usedPercent: 130, windowDurationMins: nil, resetsAt: nil).remainingPercent, 0)
    }

    func testIgnoresUnrelatedNotification() throws {
        let json = #"{"method":"account/rateLimits/updated","params":{}}"#
        XCTAssertNil(try RateLimitParser.parseResponseLine(Data(json.utf8)))
    }

    func testServerErrorDoesNotCrash() {
        let json = #"{"id":2,"error":{"code":-32600,"message":"not logged in"}}"#
        XCTAssertThrowsError(try RateLimitParser.parseResponseLine(Data(json.utf8)))
    }

    func testInstalledCodexReturnsRealLimits() async throws {
        let executable = try CodexUsageService.locateCodex()
        let response = try await CodexAppServerClient.fetch(executable: executable)
        XCTAssertNotNil(response.rateLimits.primary)
        XCTAssertNotNil(response.rateLimits.secondary)
        XCTAssertTrue(0...100 ~= response.rateLimits.primary!.remainingPercent)
        XCTAssertTrue(0...100 ~= response.rateLimits.secondary!.remainingPercent)
    }
}
