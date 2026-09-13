import Foundation
import XCTest
@testable import ICCeryCore

/// ``ApproximateLab`` sanity tests (issue #147).
///
/// These are loose sanity checks on a fixed-matrix approximation — not
/// ColorSync goldens.
final class ApproximateLabTests: XCTestCase {

    func testWhiteMapsToHighLStar() {
        let lab = ApproximateLab.srgb8ToLab(r: 255, g: 255, b: 255)
        XCTAssertGreaterThan(lab.l, 95)
        XCTAssertEqual(lab.a, 0, accuracy: 2)
        XCTAssertEqual(lab.b, 0, accuracy: 2)
    }

    func testBlackMapsToZeroLStar() {
        let lab = ApproximateLab.srgb8ToLab(r: 0, g: 0, b: 0)
        XCTAssertEqual(lab.l, 0, accuracy: 1)
    }

    func testPureRedIsChromatic() {
        let lab = ApproximateLab.srgb8ToLab(r: 255, g: 0, b: 0)
        // sRGB red ≈ Lab D50 (54, 81, 70) — loose bounds only.
        XCTAssertGreaterThan(lab.l, 40)
        XCTAssertLessThan(lab.l, 65)
        XCTAssertGreaterThan(lab.a, 60)
        XCTAssertGreaterThan(lab.b, 40)
    }

    func testMidGreyIsNeutral() {
        let lab = ApproximateLab.srgb8ToLab(r: 128, g: 128, b: 128)
        XCTAssertGreaterThan(lab.l, 45)
        XCTAssertLessThan(lab.l, 65)
        XCTAssertEqual(lab.a, 0, accuracy: 1)
        XCTAssertEqual(lab.b, 0, accuracy: 1)
    }
}
