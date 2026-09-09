import Foundation
import Testing
@testable import ICCeryCore

@Suite("ProfcheckParser")
struct ProfcheckParserTests {

    @Test("Prefers JSON report with de2000 keys")
    func jsonReport() {
        let output = """
        No of test patches = 52
        {"event": "report", "peak_de2000": 2.41, "avg_de2000": 0.85, "rms": 1.02}
        Profile check complete, errors(CIEDE2000): max. = 9.99, avg. = 9.99, RMS = 9.99
        """
        let report = ProfcheckParser.parse(output)
        #expect(report.isValid == true)
        #expect(report.patchCount == 52)
        #expect(report.avgDE == 0.85)
        #expect(report.maxDE == 2.41)
        #expect(report.rmsDE == 1.02)
        #expect(report.status == .excellent)
    }

    @Test("Falls back to legacy text")
    func legacyText() {
        let output = """
        No of test patches = 120
        Profile check complete, errors(CIEDE2000): max. = 3.50, avg. = 1.80, RMS = 0.95
        """
        let report = ProfcheckParser.parse(output)
        #expect(report.isValid == true)
        #expect(report.patchCount == 120)
        #expect(report.avgDE == 1.80)
        #expect(report.maxDE == 3.50)
        #expect(report.rmsDE == 0.95)
        #expect(report.status == .good)
    }

    @Test("Broad regex fallback")
    func regexFallback() {
        let output = """
        No of test patches = 10
        avg = 4.25
        max = 6.10
        rms = 2.30
        """
        let report = ProfcheckParser.parse(output)
        #expect(report.isValid == true)
        #expect(report.avgDE == 4.25)
        #expect(report.maxDE == 6.10)
        #expect(report.rmsDE == 2.30)
        #expect(report.status == .poor)
    }

    @Test("Unparseable output warns, not zeros")
    func unparseable() {
        let output = "some random text without metrics"
        let report = ProfcheckParser.parse(output)
        #expect(report.isValid == false)
        #expect(report.warning != nil)
        #expect(report.avgDE == nil)
    }

    @Test("Status bands")
    func statusBands() {
        #expect(VerificationStatus.from(avgDE: 0.5) == .excellent)
        #expect(VerificationStatus.from(avgDE: 1.5) == .good)
        #expect(VerificationStatus.from(avgDE: 2.5) == .acceptable)
        #expect(VerificationStatus.from(avgDE: 4.0) == .poor)
    }
}
