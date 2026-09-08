import Testing
import Foundation
@testable import ICCeryCore

@Suite("BinaryResolver")
struct BinaryResolverTests {

    private func makeTree(_ body: (URL) throws -> Void) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iccery-resolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try body(root)
        return root
    }

    private func touch(_ url: URL, executable: Bool = true) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data())
        if executable {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path
            )
        }
    }

    @Test func overrideDirWinsWhenFileExists() throws {
        let override = try makeTree { root in
            try touch(root.appendingPathComponent("targen"))
        }
        let bundled = try makeTree { _ in }
        let r = BinaryResolver(bundledRoot: bundled, overrideDir: override)
        #expect(r.resolve("targen") == override.appendingPathComponent("targen"))
    }

    @Test func overrideFallsThroughWhenMissing() throws {
        let override = try makeTree { _ in }
        let bundled = try makeTree { root in
            let dir = root.appendingPathComponent("macos-universal")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try touch(dir.appendingPathComponent("instlist"))
        }
        let r = BinaryResolver(bundledRoot: bundled, overrideDir: override)
        #expect(r.resolve("targen").path.contains("macos-universal/targen"))
    }

    @Test func universalPreferredWhenMarkerPresent() throws {
        let bundled = try makeTree { root in
            for dir in ["macos-universal", "macos-x86_64"] {
                let d = root.appendingPathComponent(dir)
                try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                try touch(d.appendingPathComponent("instlist"))
            }
        }
        let r = BinaryResolver(bundledRoot: bundled)
        #expect(r.platformDir() == "macos-universal")
    }

    @Test func fallsBackToArchDir() throws {
        let bundled = try makeTree { root in
            let d = root.appendingPathComponent("macos-x86_64")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try touch(d.appendingPathComponent("instlist"))
        }
        let r = BinaryResolver(
            bundledRoot: bundled,
            archDirs: ["macos-universal", "macos-x86_64"]
        )
        #expect(r.platformDir() == "macos-x86_64")
    }

    @Test func missingEverythingReturnsConstructedPath() throws {
        let bundled = try makeTree { _ in }
        let r = BinaryResolver(bundledRoot: bundled)
        // v1 semantic: path is returned; spawn surfaces the error.
        #expect(r.resolve("targen").path.hasSuffix("macos-universal/targen"))
        #expect(!r.exists(r.resolve("targen")))
    }

    @Test func mockAndGamutPaths() throws {
        let r = BinaryResolver(bundledRoot: URL(fileURLWithPath: "/x"))
        #expect(r.mock("chartread").path == "/x/mocks/chartread.mock")
        #expect(r.referenceGamut("sRGB.gam").path == "/x/reference_gamuts/sRGB.gam")
    }
}
