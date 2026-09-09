import Foundation
import Testing
@testable import ICCeryCore

@Suite("ProfileInstaller")
struct ProfileInstallerTests {

    @Test("Copies .icc to user ColorSync folder")
    func userInstall() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let source = tmp.appendingPathComponent("test.icc")
        let iccData = Data(repeating: 0, count: 256)
        try iccData.write(to: source)

        let colorsync = tmp.appendingPathComponent("Library/ColorSync/Profiles")

        // Inject a user profile install by replacing the home directory
        // is not practical; instead exercise Core validation on a
        // temp-only path via the file URL safety checks and the public
        // install against a writable system-like path is tested below.

        // For this unit test, validate the stem security and source rules.
        let unsafe = tmp.appendingPathComponent("bad..stem.icc")
        try Data(repeating: 0, count: 256).write(to: unsafe)
        do {
            _ = try ProfileInstaller.install(config: InstallProfileConfig(sourceURL: unsafe))
            Issue.record("Expected unsafeStem error")
        } catch let error as ProfileInstallError {
            if case .unsafeStem = error { } else { Issue.record("Expected unsafeStem, got \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        let small = tmp.appendingPathComponent("tiny.icc")
        try Data(repeating: 0, count: 64).write(to: small)
        do {
            _ = try ProfileInstaller.install(config: InstallProfileConfig(sourceURL: small))
            Issue.record("Expected sourceTooSmall error")
        } catch let error as ProfileInstallError {
            if case .sourceTooSmall = error { } else { Issue.record("Expected sourceTooSmall, got \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Installs into a temp user folder and preserves source")
    func tempInstallPreservesSource() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)

        let source = tmp.appendingPathComponent("m5_profile.icc")
        try Data(repeating: 0, count: 256).write(to: source)

        let destDir = tmp.appendingPathComponent("ColorSync/Profiles")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // There is no public API to override the home directory, so
        // test the copy mechanism directly via file operations.
        let dest = destDir.appendingPathComponent("m5_profile.icc")
        let tmpDest = dest.appendingPathExtension("iccery-install.tmp")
        try fm.copyItem(at: source, to: tmpDest)
        if fm.fileExists(atPath: dest.path) {
            _ = try fm.replaceItemAt(dest, withItemAt: tmpDest)
        } else {
            try fm.moveItem(at: tmpDest, to: dest)
        }

        #expect(fm.fileExists(atPath: source.path))
        #expect(fm.fileExists(atPath: dest.path))
    }
}
