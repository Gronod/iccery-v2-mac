import Testing
import Foundation
@testable import ICCeryCore

@Suite("ArgsBuilder")
struct ArgsBuilderTests {

    // MARK: - option

    @Test("option: nil emits nothing")
    func optionNil() {
        #expect(ArgsBuilder.option("-f", nil) == [])
    }

    @Test("option: present value emits flag and value verbatim")
    func optionPresent() {
        #expect(ArgsBuilder.option("-f", "abc") == ["-f", "abc"])
        #expect(ArgsBuilder.option("-f", "") == ["-f", ""])
        #expect(ArgsBuilder.option("-f", "  padded  ") == ["-f", "  padded  "])
    }

    // MARK: - optionIfNonEmpty

    @Test("optionIfNonEmpty: nil and empty emit nothing")
    func optionIfNonEmptyNilEmpty() {
        #expect(ArgsBuilder.optionIfNonEmpty("-d", nil) == [])
        #expect(ArgsBuilder.optionIfNonEmpty("-d", "") == [])
    }

    @Test("optionIfNonEmpty: whitespace-only emits nothing")
    func optionIfNonEmptyWhitespace() {
        #expect(ArgsBuilder.optionIfNonEmpty("-d", "   ") == [])
        #expect(ArgsBuilder.optionIfNonEmpty("-d", " \t\n ") == [])
    }

    @Test("optionIfNonEmpty: trims surrounding whitespace")
    func optionIfNonEmptyTrims() {
        #expect(ArgsBuilder.optionIfNonEmpty("-d", "  label  ") == ["-d", "label"])
        #expect(ArgsBuilder.optionIfNonEmpty("-d", "\tcal.cal\n") == ["-d", "cal.cal"])
    }

    // MARK: - optionUnlessApprox

    @Test("optionUnlessApprox: nil emits nothing")
    func optionUnlessApproxNil() {
        #expect(ArgsBuilder.optionUnlessApprox("-N", nil, skip: 0.50) == [])
    }

    @Test("optionUnlessApprox: exact skip value emits nothing")
    func optionUnlessApproxExactSkip() {
        #expect(ArgsBuilder.optionUnlessApprox("-N", 0.50, skip: 0.50) == [])
        #expect(ArgsBuilder.optionUnlessApprox("-V", 1.0, skip: 1.0) == [])
    }

    @Test("optionUnlessApprox: within epsilon emits nothing")
    func optionUnlessApproxWithinEpsilon() {
        #expect(ArgsBuilder.optionUnlessApprox("-N", 0.5005, skip: 0.50) == [])
        #expect(ArgsBuilder.optionUnlessApprox("-V", 0.9995, skip: 1.0) == [])
    }

    @Test("optionUnlessApprox: outside epsilon emits flag")
    func optionUnlessApproxOutsideEpsilon() {
        #expect(ArgsBuilder.optionUnlessApprox("-N", 0.75, skip: 0.50) == ["-N", "0.75"])
        #expect(ArgsBuilder.optionUnlessApprox("-V", 1.50, skip: 1.0) == ["-V", "1.50"])
        #expect(ArgsBuilder.optionUnlessApprox("-N", 0.498, skip: 0.50) == ["-N", "0.50"])
    }

    @Test("optionUnlessApprox: POSIX formatting is locale-stable")
    func optionUnlessApproxPOSIX() {
        // 1234.5 must never produce a grouping separator or comma decimal.
        #expect(ArgsBuilder.optionUnlessApprox("-p", 1234.5, skip: 1.0) == ["-p", "1234.50"])
        #expect(ArgsBuilder.optionUnlessApprox("-p", 2.0, skip: 1.0) == ["-p", "2.00"])
    }

    @Test("optionUnlessApprox: custom epsilon and format honoured")
    func optionUnlessApproxCustom() {
        #expect(ArgsBuilder.optionUnlessApprox("-x", 1.005, skip: 1.0, epsilon: 0.01) == [])
        #expect(ArgsBuilder.optionUnlessApprox("-x", 1.5, skip: 1.0, format: "%.1f") == ["-x", "1.5"])
    }

    // MARK: - flag

    @Test("flag: true emits the bare flag")
    func flagTrue() {
        #expect(ArgsBuilder.flag("-G", when: true) == ["-G"])
        #expect(ArgsBuilder.flag("-r", when: true) == ["-r"])
    }

    @Test("flag: false emits nothing")
    func flagFalse() {
        #expect(ArgsBuilder.flag("-G", when: false) == [])
        #expect(ArgsBuilder.flag("-r", when: false) == [])
    }
}
