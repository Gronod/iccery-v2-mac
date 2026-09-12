import XCTest
import Foundation
@testable import ICCeryCore

final class ArgsBuilderTests: XCTestCase {

    // MARK: - option

    func testOptionNil() {
        XCTAssertEqual(ArgsBuilder.option("-f", nil), [])
    }

    func testOptionPresent() {
        XCTAssertEqual(ArgsBuilder.option("-f", "abc"), ["-f", "abc"])
        XCTAssertEqual(ArgsBuilder.option("-f", ""), ["-f", ""])
        XCTAssertEqual(ArgsBuilder.option("-f", "  padded  "), ["-f", "  padded  "])
    }

    // MARK: - optionIfNonEmpty

    func testOptionIfNonEmptyNilEmpty() {
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", nil), [])
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", ""), [])
    }

    func testOptionIfNonEmptyWhitespace() {
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", "   "), [])
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", " \t\n "), [])
    }

    func testOptionIfNonEmptyTrims() {
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", "  label  "), ["-d", "label"])
        XCTAssertEqual(ArgsBuilder.optionIfNonEmpty("-d", "\tcal.cal\n"), ["-d", "cal.cal"])
    }

    // MARK: - optionUnlessApprox

    func testOptionUnlessApproxNil() {
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-N", nil, skip: 0.50), [])
    }

    func testOptionUnlessApproxExactSkip() {
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-N", 0.50, skip: 0.50), [])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-V", 1.0, skip: 1.0), [])
    }

    func testOptionUnlessApproxWithinEpsilon() {
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-N", 0.5005, skip: 0.50), [])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-V", 0.9995, skip: 1.0), [])
    }

    func testOptionUnlessApproxOutsideEpsilon() {
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-N", 0.75, skip: 0.50), ["-N", "0.75"])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-V", 1.50, skip: 1.0), ["-V", "1.50"])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-N", 0.498, skip: 0.50), ["-N", "0.50"])
    }

    func testOptionUnlessApproxPOSIX() {
        // 1234.5 must never produce a grouping separator or comma decimal.
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-p", 1234.5, skip: 1.0), ["-p", "1234.50"])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-p", 2.0, skip: 1.0), ["-p", "2.00"])
    }

    func testOptionUnlessApproxCustom() {
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-x", 1.005, skip: 1.0, epsilon: 0.01), [])
        XCTAssertEqual(ArgsBuilder.optionUnlessApprox("-x", 1.5, skip: 1.0, format: "%.1f"), ["-x", "1.5"])
    }

    // MARK: - flag

    func testFlagTrue() {
        XCTAssertEqual(ArgsBuilder.flag("-G", when: true), ["-G"])
        XCTAssertEqual(ArgsBuilder.flag("-r", when: true), ["-r"])
    }

    func testFlagFalse() {
        XCTAssertEqual(ArgsBuilder.flag("-G", when: false), [])
        XCTAssertEqual(ArgsBuilder.flag("-r", when: false), [])
    }
}
