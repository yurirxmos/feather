import XCTest
@testable import FeatherCore

final class PanelPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = CGSize(width: 560, height: 180)

    func testPlacesBelowWindowWhenThereIsRoom() {
        let origin = PanelPlacement.origin(panelSize: panel, windowFrame: CGRect(x: 400, y: 500, width: 600, height: 300), visibleFrame: screen)
        XCTAssertEqual(origin, CGPoint(x: 420, y: 310))
    }

    func testPlacesAboveWindowWhenBelowDoesNotFit() {
        let origin = PanelPlacement.origin(panelSize: panel, windowFrame: CGRect(x: 400, y: 100, width: 600, height: 200), visibleFrame: screen)
        XCTAssertEqual(origin, CGPoint(x: 420, y: 310))
    }

    func testClampsHorizontalPosition() {
        let origin = PanelPlacement.origin(panelSize: panel, windowFrame: CGRect(x: -300, y: 500, width: 300, height: 200), visibleFrame: screen)
        XCTAssertEqual(origin.x, 18)
    }

    func testConvertsAccessibilityFrameAgainstPrimaryDisplayNotFocusedDisplay() {
        let accessibilityFrame = CGRect(x: 1600, y: 200, width: 800, height: 500)
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(PanelPlacement.appKitFrame(fromAccessibilityFrame: accessibilityFrame, primaryScreenFrame: primary), CGRect(x: 1600, y: 200, width: 800, height: 500))
        XCTAssertNotEqual(PanelPlacement.appKitFrame(fromAccessibilityFrame: accessibilityFrame, primaryScreenFrame: secondary).origin.y, 200)
    }
}
