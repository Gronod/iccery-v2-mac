import Foundation
import Testing
@testable import ICCeryCore

@Suite("ColprofProgress")
struct ColprofProgressTests {

    @Test("Classifies gamut mapping")
    func gamutMapping() {
        #expect(ColprofProgressClassifier.classify(line: "Gamut mapping calculation in progress") == .gamutMapping)
    }

    @Test("Classifies fitting or clut")
    func fitting() {
        #expect(ColprofProgressClassifier.classify(line: "Fitting cLUT grid points") == .fittingClut)
        #expect(ColprofProgressClassifier.classify(line: "clut table") == .fittingClut)
    }

    @Test("Classifies writing")
    func writing() {
        #expect(ColprofProgressClassifier.classify(line: "Writing ICC profile header") == .writingIcc)
        #expect(ColprofProgressClassifier.classify(line: "icc profile written") == .writingIcc)
    }
}
