import Foundation
import Testing
@testable import ICCery

/// Direct contracts for the shared logged-run helper (issue #80).
///
/// `runLogged` owns the running-flag transition (`false → true → false`)
/// and the log-reset decision; these tests pin both sides of the
/// contract plus the coalesced `@MainActor` log hop.
@Suite("ProcessRunSupport runLogged")
@MainActor
struct ProcessRunSupportTests {

    private struct SentinelError: Error {}

    @Test("Success: running transitions [true, false], log resets once, batches reach the main actor, value preserved")
    func successTransitions() async throws {
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

        #expect(result == 42)
        #expect(running == [true, false])
        #expect(resets == 1)

        // The sink hops back through a main-actor Task; yield until the
        // coalesced batch lands.
        for _ in 0..<200 where received.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(received == ["alpha", "beta"])
    }

    @Test("Failure: running still transitions [true, false], log resets once, error is rethrown")
    func failureTransitions() async throws {
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
            Issue.record("Expected runLogged to rethrow")
        } catch is SentinelError {
            // Expected path.
        }

        #expect(running == [true, false])
        #expect(resets == 1)
    }
}
