import Foundation
import XCTest
@testable import ICCeryCore

/// A `FileManager` subclass that reports a temporary directory as the
/// user home, so `ProfileInstaller` can be tested without writing to the
/// real `~/Library/ColorSync/Profiles`.
private final class TestFileManager: FileManager {
    let tempHome: URL

    init(home: URL) {
        self.tempHome = home
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        tempHome
    }
}

final class ProfileInstallerTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    private func makeSource(
        at dir: URL,
        name: String,
        bytes: [UInt8] = Array(repeating: 0, count: 256)
    ) throws -> URL {
        let url = dir.appendingPathComponent(name)
        let data = Data(bytes)
        try data.write(to: url)
        return url
    }

    func testUserInstall() throws {
        let fm = FileManager.default
        let tmp = try makeTempDir()
        let testFM = TestFileManager(home: tmp)
        let source = try makeSource(at: tmp, name: "test.icc")

        let result = try ProfileInstaller.install(
            config: InstallProfileConfig(sourceURL: source),
            fileManager: testFM
        )

        XCTAssertTrue(result.registered)
        XCTAssertFalse(result.overwritten)
        XCTAssertFalse(result.renamed)
        XCTAssertTrue(result.destPath.hasSuffix("test.icc"))
        XCTAssertTrue(fm.fileExists(atPath: result.destPath))
    }

    func testOverwriteSucceeds() throws {
        let fm = FileManager.default
        let tmp = try makeTempDir()
        let testFM = TestFileManager(home: tmp)
        let source = try makeSource(at: tmp, name: "m5_profile.icc", bytes: (0..<256).map { UInt8($0) })

        // First install.
        let first = try ProfileInstaller.install(
            config: InstallProfileConfig(sourceURL: source),
            fileManager: testFM
        )
        XCTAssertFalse(first.overwritten)

        // Change the source contents.
        let newBytes: [UInt8] = (0..<256).map { UInt8(($0 + 100) % 256) }
        try Data(newBytes).write(to: source)

        let options = InstallProfileOptions(
            forceOverwrite: true,
            preferSystem: false,
            collisionPolicy: .overwrite,
            openColorPanel: false
        )
        let second = try ProfileInstaller.install(
            config: InstallProfileConfig(sourceURL: source, options: options),
            fileManager: testFM
        )

        XCTAssertTrue(second.overwritten)
        XCTAssertFalse(second.renamed)
        XCTAssertTrue(fm.fileExists(atPath: second.destPath))
        let installed = try Data(contentsOf: URL(fileURLWithPath: second.destPath))
        XCTAssertEqual(Array(installed), newBytes)
    }

    func testPreservesIcmExtension() throws {
        let tmp = try makeTempDir()
        let testFM = TestFileManager(home: tmp)
        let source = try makeSource(at: tmp, name: "m5_profile.icm")

        let result = try ProfileInstaller.install(
            config: InstallProfileConfig(sourceURL: source),
            fileManager: testFM
        )

        XCTAssertEqual(URL(fileURLWithPath: result.destPath).pathExtension, "icm")
        XCTAssertTrue(result.destPath.hasSuffix("m5_profile.icm"))
    }

    func testRejectsParentTraversal() throws {
        let fm = FileManager.default
        let tmp = try makeTempDir()

        // Create a real file in the parent of `tmp` with a path that contains
        // a literal ".." component.
        let parent = tmp.deletingLastPathComponent()
        let naughtyName = "naughty-\(UUID().uuidString).icc"
        let realFile = parent.appendingPathComponent(naughtyName)
        _ = try makeSource(at: parent, name: naughtyName)
        defer { try? fm.removeItem(at: realFile) }

        let sourceURL = tmp
            .appendingPathComponent("..")
            .appendingPathComponent(naughtyName)
        XCTAssertTrue(fm.fileExists(atPath: sourceURL.path))

        do {
            _ = try ProfileInstaller.install(config: InstallProfileConfig(sourceURL: sourceURL))
            XCTFail("Expected unsafeStem error")
        } catch let error as ProfileInstallError {
            if case .unsafeStem = error { } else { XCTFail("Expected unsafeStem, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAllowsDoubleDotStem() throws {
        let fm = FileManager.default
        let tmp = try makeTempDir()
        let testFM = TestFileManager(home: tmp)
        let source = try makeSource(at: tmp, name: "foo..bar.icc")

        let result = try ProfileInstaller.install(
            config: InstallProfileConfig(sourceURL: source),
            fileManager: testFM
        )

        XCTAssertTrue(result.destPath.hasSuffix("foo..bar.icc"))
        XCTAssertTrue(fm.fileExists(atPath: result.destPath))
    }

    func testRejectsSmallSource() throws {
        let tmp = try makeTempDir()
        let source = tmp.appendingPathComponent("tiny.icc")
        try Data(repeating: 0, count: 64).write(to: source)

        do {
            _ = try ProfileInstaller.install(config: InstallProfileConfig(sourceURL: source))
            XCTFail("Expected sourceTooSmall error")
        } catch let error as ProfileInstallError {
            if case .sourceTooSmall = error { } else { XCTFail("Expected sourceTooSmall, got \(error)") }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
