import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Dataset-import error contracts through the
/// `importMeasurementDataset(from:)` seam (issue #80): parser and I/O
/// failures must surface identically as a single `.error` Notice.
@MainActor
final class TargetWorkflowViewModelTests: XCTestCase {

    func testMalformedDatasetNotice() throws {
        let env = try TestAppEnvironment.make()
        defer { env.cleanup() }
        let vm = TargetWorkflowViewModel(environment: env.environment)

        let bad = env.root.appendingPathComponent("broken.ti3")
        try Data("this is not CGATS data".utf8).write(to: bad)

        vm.importMeasurementDataset(from: bad)

        let notice = try XCTUnwrap(vm.wizard.notice)
        XCTAssertEqual(notice.kind, .error)
        XCTAssertTrue(notice.text.hasPrefix("Import failed:"))
    }

    func testMissingDatasetNotice() throws {
        let env = try TestAppEnvironment.make()
        defer { env.cleanup() }
        let vm = TargetWorkflowViewModel(environment: env.environment)

        let missing = env.root.appendingPathComponent("does-not-exist.ti3")
        vm.importMeasurementDataset(from: missing)

        let notice = try XCTUnwrap(vm.wizard.notice)
        XCTAssertEqual(notice.kind, .error)
        XCTAssertTrue(notice.text.hasPrefix("Import failed:"))
    }
}
