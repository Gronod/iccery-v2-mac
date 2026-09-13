import Foundation
import XCTest
@testable import ICCeryCore

/// Issue #149 — `.icceryproj` schema: snake_case keys, strict
/// `schema_version == 1`, and save-time refusal for empty/illegal
/// basename and empty/unsafe cwd (#59/#60/R11).
final class ICCeryProjectTests: XCTestCase {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-proj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeProject(
        basename: String = "run-1",
        cwd: String = "/tmp"
    ) -> ICCeryProject {
        ICCeryProject(
            name: "Run One",
            basename: basename,
            cwd: cwd,
            profileBasename: "run-1",
            printerID: "Mock_Queue",
            printerDisplayName: "Mock Queue",
            mediaRecipeID: "recipe-1",
            presetID: "preset-std-rgb",
            calibrationURL: "/tmp/r.cal",
            lastVerification: VerificationSnapshot(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                avgDE00: 0.8, maxDE00: 2.1,
                status: "excellent", profileFilename: "run-1.icc"))
    }

    // MARK: - Round trip / keys

    func testSnakeCaseRoundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.icceryproj")

        let project = makeProject()
        try project.save(to: url)
        let loaded = try ICCeryProject.load(from: url)

        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.basename, "run-1")
        XCTAssertEqual(loaded.cwd, "/tmp")
        XCTAssertEqual(loaded.profileBasename, "run-1")
        XCTAssertEqual(loaded.printerID, "Mock_Queue")
        XCTAssertEqual(loaded.mediaRecipeID, "recipe-1")
        XCTAssertEqual(loaded.presetID, "preset-std-rgb")
        XCTAssertEqual(loaded.calibrationURL, "/tmp/r.cal")
        XCTAssertEqual(loaded.lastVerification?.avgDE00, 0.8)
        XCTAssertEqual(loaded.lastVerification?.maxDE00, 2.1)
        XCTAssertEqual(loaded.lastVerification?.status, "excellent")
        XCTAssertEqual(loaded.lastVerification?.profileFilename, "run-1.icc")

        let raw = try String(contentsOf: url, encoding: .utf8)
        for key in [
            "\"schema_version\"", "\"profile_basename\"",
            "\"printer_id\"", "\"printer_display_name\"",
            "\"media_recipe_id\"", "\"preset_id\"",
            "\"calibration_url\"", "\"last_verification\"",
            "\"avg_de00\"", "\"max_de00\"", "\"profile_filename\"",
        ] {
            XCTAssertTrue(raw.contains(key), "missing key \(key)")
        }
    }

    func testOptionalFieldsDecodeWhenAbsent() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("min.icceryproj")
        let json = """
        {
          "schema_version": 1,
          "name": "Minimal",
          "basename": "abc",
          "cwd": "/tmp",
          "updated": "2026-09-13T00:00:00Z"
        }
        """
        try json.write(to: url, atomically: true, encoding: .utf8)

        let loaded = try ICCeryProject.load(from: url)
        XCTAssertEqual(loaded.basename, "abc")
        XCTAssertNil(loaded.mediaRecipeID)
        XCTAssertNil(loaded.presetID)
        XCTAssertNil(loaded.lastVerification)
        XCTAssertNil(loaded.calibrationURL)
    }

    // MARK: - Schema gate

    func testSchemaVersion2Throws() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("v2.icceryproj")
        try """
        {"schema_version": 2, "name": "x", "basename": "abc",
         "cwd": "/tmp", "future_field": [1, 2]}
        """.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ICCeryProject.load(from: url)) { error in
            guard case ICCeryProject.ValidationError.unsupportedSchema(2)
                    = error else {
                return XCTFail("expected unsupportedSchema, got \(error)")
            }
            XCTAssertEqual(
                error.localizedDescription,
                "This project file is not schema 1.")
        }
    }

    func testMissingSchemaVersionThrows() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("noversion.icceryproj")
        try "{\"basename\": \"abc\", \"cwd\": \"/tmp\"}"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ICCeryProject.load(from: url))
    }

    // MARK: - Validation

    func testEmptyBasenameRefusesSave() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.icceryproj")
        XCTAssertThrowsError(
            try makeProject(basename: "").save(to: url)
        ) { error in
            XCTAssertEqual(
                error as? ICCeryProject.ValidationError, .emptyBasename)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testIllegalBasenameRefusesSave() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        for bad in ["a/b", "a\\b", "..", "x..y"] {
            XCTAssertThrowsError(
                try makeProject(basename: bad).save(
                    to: dir.appendingPathComponent("p.icceryproj"))
            ) { error in
                guard case ICCeryProject.ValidationError.invalidBasename
                        = error else {
                    return XCTFail("expected invalidBasename, got \(error)")
                }
            }
        }
    }

    func testEmptyAndRelativeCwdRefuseSave() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("p.icceryproj")
        XCTAssertThrowsError(try makeProject(cwd: "").save(to: url)) { error in
            XCTAssertEqual(
                error as? ICCeryProject.ValidationError, .emptyCwd)
        }
        XCTAssertThrowsError(
            try makeProject(cwd: "relative/dir").save(to: url)
        ) { error in
            guard case ICCeryProject.ValidationError.unsafeCwd = error else {
                return XCTFail("expected unsafeCwd, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testIllegalBasenameRefusesOpen() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bad.icceryproj")
        try """
        {"schema_version": 1, "basename": "a/b", "cwd": "/tmp"}
        """.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ICCeryProject.load(from: url)) { error in
            guard case ICCeryProject.ValidationError.invalidBasename
                    = error else {
                return XCTFail("expected invalidBasename, got \(error)")
            }
        }
    }

    func testEmptyNameFallsBackToBasename() throws {
        let project = try ICCeryProject(
            name: "", basename: "stem", cwd: "/tmp").validated()
        XCTAssertEqual(project.name, "stem")
    }

    func testMissingFileThrowsOnOpen() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gone-\(UUID().uuidString).icceryproj")
        XCTAssertThrowsError(try ICCeryProject.load(from: url))
    }
}
