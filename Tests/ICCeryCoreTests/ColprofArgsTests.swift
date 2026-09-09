import Foundation
import Testing
@testable import ICCeryCore

@Suite("ColprofArgs")
struct ColprofArgsTests {

    @Test("Default algorithm and quality")
    func defaults() throws {
        let config = ColprofConfig(basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(args == ["-v", "-a", "l", "-q", "m", "target"])
    }

    @Test("FWA bare -f when empty string")
    func fwaBareFlag() throws {
        let config = ColprofConfig(fwa: "", basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(args == ["-v", "-a", "l", "-q", "m", "-f", "target"])
    }

    @Test("FWA D50 and D65 emit -f value")
    func fwaD50() throws {
        let config = ColprofConfig(fwa: "D50", basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(args.contains("-f"))
        #expect(args.contains("D50"))
        #expect(args.last == "target")
    }

    @Test("FWA none is omitted")
    func fwaNoneOmitted() throws {
        let config = ColprofConfig(fwa: "none", basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(!args.contains("-f"))
    }

    @Test("Viewing conditions skip none")
    func viewingCondNoneSkipped() throws {
        let config = ColprofConfig(
            inputViewingCond: "none",
            outputViewingCond: "mt",
            basename: "target"
        )
        let args = try ColprofArgs.build(config: config)
        #expect(!args.contains("-c"))
        #expect(args.contains("-d"))
        #expect(args.contains("mt"))
    }

    @Test("Description falls back to basename when empty")
    func descriptionFallback() throws {
        let config = ColprofConfig(description: "", basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(!args.contains("-D"))
    }

    @Test("Copyright only when non-empty")
    func copyright() throws {
        let config = ColprofConfig(copyright: "Gronod 2026", basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(args.contains("-C"))
        #expect(args.contains("Gronod 2026"))
    }

    @Test("No -u passed")
    func noProgressJsonFlag() throws {
        let config = ColprofConfig(basename: "target")
        let args = try ColprofArgs.build(config: config)
        #expect(!args.contains("-u"))
    }
}
