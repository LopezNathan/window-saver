import XCTest
@testable import Window_Saver

final class WindowMatchingTests: XCTestCase {
    private func key(title: String = "Mozilla Firefox") -> WindowKey {
        WindowKey(accessibilityIdentifier: nil, documentURL: nil, normalizedTitle: title, role: "AXWindow", subrole: "AXStandardWindow", ordinal: 0)
    }
    private func candidate(title: String) -> WindowMatchCandidate {
        WindowMatchCandidate(accessibilityIdentifier: nil, documentURL: nil, normalizedTitle: title, role: "AXWindow", subrole: "AXStandardWindow")
    }
    func testAChangedBrowserTabTitleMatchesItsOnlyCompatibleWindow() {
        XCTAssertEqual(WindowMatcher.select(key(title: "Old tab — Mozilla Firefox"), from: [candidate(title: "New tab — Mozilla Firefox")]), .match(0))
    }
    func testChangedTitlesAcrossTwoBrowserWindowsRemainAmbiguous() {
        XCTAssertEqual(WindowMatcher.select(key(title: "Old tab — Mozilla Firefox"), from: [candidate(title: "New tab — Mozilla Firefox"), candidate(title: "Other tab — Mozilla Firefox")]), .ambiguous)
    }
    func testExactTitleSelectsTheRightWindowAmongSeveral() {
        XCTAssertEqual(WindowMatcher.select(key(title: "Project — Mozilla Firefox"), from: [candidate(title: "Other — Mozilla Firefox"), candidate(title: "Project — Mozilla Firefox")]), .match(1))
    }
}
