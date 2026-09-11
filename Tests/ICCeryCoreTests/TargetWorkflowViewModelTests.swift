import Foundation
import Testing
@testable import ICCeryCore
@testable import ICCery

/// Dataset-import error contracts through the
/// `importMeasurementDataset(from:)` seam (issue #80): parser and I/O
/// failures must surface identically as a single `.error` Notice.
@Suite("TargetWorkflowViewModel dataset import")
@MainActor
struct TargetWorkflowViewModelTests {

    @Test("Malformed content (CGATSParseError) produces one .error notice prefixed 'Import failed:'")
    func malformedDatasetNotice() throws {
        let env = try TestAppEnvironment.make()
        defer { env.cleanup() }
        let vm = TargetWorkflowViewModel(environment: env.environment)

        let bad = env.root.appendingPathComponent("broken.ti3")
        try Data("this is not CGATS data".utf8).write(to: bad)

        vm.importMeasurementDataset(from: bad)

        let notice = try #require(vm.wizard.notice)
        #expect(notice.kind == .error)
        #expect(notice.text.hasPrefix("Import failed:"))
    }

    @Test("Missing file (CocoaError) produces one .error notice prefixed 'Import failed:'")
    func missingDatasetNotice() throws {
        let env = try TestAppEnvironment.make()
        defer { env.cleanup() }
        let vm = TargetWorkflowViewModel(environment: env.environment)

        let missing = env.root.appendingPathComponent("does-not-exist.ti3")
        vm.importMeasurementDataset(from: missing)

        let notice = try #require(vm.wizard.notice)
        #expect(notice.kind == .error)
        #expect(notice.text.hasPrefix("Import failed:"))
    }
}
