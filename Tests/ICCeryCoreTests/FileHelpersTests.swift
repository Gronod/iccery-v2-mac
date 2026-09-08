import Testing
import Foundation
@testable import ICCeryCore

private func tempDir(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("iccery-files-\(name)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func touch(_ url: URL, _ contents: String = "x") throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

@Suite("PathSecurity")
struct PathSecurityTests {
    @Test func rejectsTraversalAndSeparators() {
        for bad in ["a/b", "a\\b", "..", "a/../b", "", "..x"] {
            #expect(!PathSecurity.isValidBasename(bad))
            #expect(throws: PathSecurity.Error.self) {
                try PathSecurity.sanitizeBasename(bad)
            }
        }
    }

    @Test func acceptsNormalNames() {
        for good in ["target", "My Target 01", "écheneau-ümläut", "a.b"] {
            #expect(PathSecurity.isValidBasename(good))
        }
    }

    @Test func resolveSafeCwdPrefersExplicit() throws {
        let dir = try tempDir()
        #expect(PathSecurity.resolveSafeCwd(dir) == dir)
    }

    @Test func resolveSafeCwdNeverReturnsNil() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let resolved = PathSecurity.resolveSafeCwd(missing)
        #expect(FileManager.default.fileExists(atPath: resolved.path))
    }
}

@Suite("AtomicFileWriter")
struct AtomicFileWriterTests {
    @Test func writesAndLeavesNoTmp() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("state.json")
        try AtomicFileWriter.write(Data("{\"a\":1}".utf8), to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"a\":1}")
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("tmp").path))
    }

    @Test func overwritesExistingAtomically() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("f.txt")
        try AtomicFileWriter.write("one", to: url)
        try AtomicFileWriter.write("two-longer", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two-longer")
    }

    @Test func createsParentDirs() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("a/b/c/deep.json")
        try AtomicFileWriter.write("{}", to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite("ArtefactProbe")
struct ArtefactProbeTests {
    @Test func verifyProgression() throws {
        let dir = try tempDir()
        var v = ArtefactProbe.verify(basename: "t", cwd: dir)
        #expect(v == StageArtefacts())

        try touch(dir.appendingPathComponent("t.ti1"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        #expect(v.stage1Complete && !v.stage2Complete && !v.stage3Complete)

        try touch(dir.appendingPathComponent("t.ti2"))
        try touch(dir.appendingPathComponent("t.ti3"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        #expect(v.stage2Complete && v.stage3Complete && !v.stage4Complete)

        try touch(dir.appendingPathComponent("t.icc"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        #expect(v.stage4Complete && v.profilePath?.pathExtension == "icc")
    }

    @Test func icmWinsOverIcc() throws {
        let dir = try tempDir()
        try touch(dir.appendingPathComponent("p.icc"))
        try touch(dir.appendingPathComponent("p.icm"))
        let profile = ArtefactProbe.resolveProfile(basename: "p", cwd: dir)
        #expect(profile?.pathExtension == "icm")
    }

    @Test func enumeratesPassesPagesAndCAL() throws {
        let dir = try tempDir()
        for name in [
            "t.ti1", "t.ti2", "t.tif", "t.2.tif", "t_03.tif",
            "t.ti3", "t_pass1.ti3", "t_pass2.ti3",
            "t.icc", "t.gam",
            "CAL_t.ti1", "CAL_t.cal",
            // must NOT match:
            "other.ti1", "t.txt", "CAL_other.ti1",
        ] { try touch(dir.appendingPathComponent(name)) }

        let names = ArtefactProbe.existingArtefacts(basename: "t", cwd: dir)
            .map(\.lastPathComponent)
        for expected in [
            "t.ti1", "t.ti2", "t.tif", "t.2.tif", "t_03.tif",
            "t.ti3", "t_pass1.ti3", "t_pass2.ti3",
            "t.icc", "t.gam", "CAL_t.ti1", "CAL_t.cal",
        ] {
            #expect(names.contains(expected), "missing \(expected)")
        }
        #expect(!names.contains("other.ti1"))
        #expect(!names.contains("t.txt"))
        #expect(!names.contains("CAL_other.ti1"))
    }

    @Test func emptyDirReturnsEmpty() throws {
        let dir = try tempDir()
        #expect(ArtefactProbe.existingArtefacts(basename: "x", cwd: dir).isEmpty)
    }
}
