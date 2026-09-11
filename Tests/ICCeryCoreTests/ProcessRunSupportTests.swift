import Foundation
import XCTest
@testable import ICCery

/// Direct contracts for the shared logged-run helper (issue #80).
///
/// `runLogged` owns the running-flag transition (`false → true → false`)
/// and the log-reset decision; these tests pin both sides of the
/// contract plus the coalesced `@MainActor` log hop.
@MainActor
final class ProcessRunSupportTests: XCTestCase {

    private struct SentinelError: Error {}

    func testSuccessTransitions() async throws {
        var running: [Bool] = []
        var resets = 0
        var received: [String] = []

        let result = try await ProcessRunSupport.runLogged(
            setRunning: { running.append($0) },
            resetLog: { resets += 1 },
            onLog: { batch in
                MainActor.assertIsolated()
                received.append(contentsOf: batch)
            }
        ) { onLog in
            onLog(["alpha", "beta"])
            return 42
        }

        XCTAssertEqual(result, 42)
        XCTAssertEqual(running, [true, false])
        XCTAssertEqual(resets, 1)

        // The sink hops back through a main-actor Task; yield until the
        // coalesced batch lands.
        for _ in 0..<200 where received.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(received, ["alpha", "beta"])
    }

    func testFailureTransitions() async throws {
        var running: [Bool] = []
        var resets = 0

        do {
            _ = try await ProcessRunSupport.runLogged(
                setRunning: { running.append($0) },
                resetLog: { resets += 1 },
                onLog: { _ in }
            ) { _ -> Int in
                throw SentinelError()
            }
            XCTFail("Expected runLogged to rethrow")
        } catch is SentinelError {
            // Expected path.
        }

        XCTAssertEqual(running, [true, false])
        XCTAssertEqual(resets, 1)
    }
}
