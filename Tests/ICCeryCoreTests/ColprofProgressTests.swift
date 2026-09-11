import Foundation
import XCTest
@testable import ICCeryCore

final class ColprofProgressTests: XCTestCase {

    func testGamutMapping() {
        XCTAssertEqual(ColprofProgressClassifier.classify(line: "Gamut mapping calculation in progress"), .gamutMapping)
    }

    func testFitting() {
        XCTAssertEqual(ColprofProgressClassifier.classify(line: "Fitting cLUT grid points"), .fittingClut)
        XCTAssertEqual(ColprofProgressClassifier.classify(line: "clut table"), .fittingClut)
    }

    func testWriting() {
        XCTAssertEqual(ColprofProgressClassifier.classify(line: "Writing ICC profile header"), .writingIcc)
        XCTAssertEqual(ColprofProgressClassifier.classify(line: "icc profile written"), .writingIcc)
    }
}
