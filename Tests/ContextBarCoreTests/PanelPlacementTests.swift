import XCTest
@testable import ContextBarCore

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
}
