import XCTest
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

final class PathSecurityTests: XCTestCase {
    func testRejectsTraversalAndSeparators() {
        for bad in ["a/b", "a\\b", "..", "a/../b", "", "..x"] {
            XCTAssertFalse(PathSecurity.isValidBasename(bad))
            XCTAssertThrowsError(try PathSecurity.sanitizeBasename(bad)) { error in
                XCTAssertTrue(error is PathSecurity.Error)
            }
        }
    }

    func testAcceptsNormalNames() {
        for good in ["target", "My Target 01", "écheneau-ümläut", "a.b"] {
            XCTAssertTrue(PathSecurity.isValidBasename(good))
        }
    }

    func testResolveSafeCwdPrefersExplicit() throws {
        let dir = try tempDir()
        XCTAssertEqual(PathSecurity.resolveSafeCwd(dir), dir)
    }

    func testResolveSafeCwdNeverReturnsNil() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let resolved = PathSecurity.resolveSafeCwd(missing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path))
    }
}

final class AtomicFileWriterTests: XCTestCase {
    func testWritesAndLeavesNoTmp() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("state.json")
        try AtomicFileWriter.write(Data("{\"a\":1}".utf8), to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{\"a\":1}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("tmp").path))
    }

    func testOverwritesExistingAtomically() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("f.txt")
        try AtomicFileWriter.write("one", to: url)
        try AtomicFileWriter.write("two-longer", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "two-longer")
    }

    func testCreatesParentDirs() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("a/b/c/deep.json")
        try AtomicFileWriter.write("{}", to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}

final class ArtefactProbeTests: XCTestCase {
    func testVerifyProgression() throws {
        let dir = try tempDir()
        var v = ArtefactProbe.verify(basename: "t", cwd: dir)
        XCTAssertEqual(v, StageArtefacts())

        try touch(dir.appendingPathComponent("t.ti1"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        XCTAssertTrue(v.stage1Complete && !v.stage2Complete && !v.stage3Complete)

        try touch(dir.appendingPathComponent("t.ti2"))
        try touch(dir.appendingPathComponent("t.ti3"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        XCTAssertTrue(v.stage2Complete && v.stage3Complete && !v.stage4Complete)

        try touch(dir.appendingPathComponent("t.icc"))
        v = ArtefactProbe.verify(basename: "t", cwd: dir)
        XCTAssertTrue(v.stage4Complete && v.profilePath?.pathExtension == "icc")
    }

    func testIcmWinsOverIcc() throws {
        let dir = try tempDir()
        try touch(dir.appendingPathComponent("p.icc"))
        try touch(dir.appendingPathComponent("p.icm"))
        let profile = ArtefactProbe.resolveProfile(basename: "p", cwd: dir)
        XCTAssertEqual(profile?.pathExtension, "icm")
    }

    func testEnumeratesPassesPagesAndCAL() throws {
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
            XCTAssertTrue(names.contains(expected), "missing \(expected)")
        }
        XCTAssertFalse(names.contains("other.ti1"))
        XCTAssertFalse(names.contains("t.txt"))
        XCTAssertFalse(names.contains("CAL_other.ti1"))
    }

    func testEmptyDirReturnsEmpty() throws {
        let dir = try tempDir()
        XCTAssertTrue(ArtefactProbe.existingArtefacts(basename: "x", cwd: dir).isEmpty)
    }
}
