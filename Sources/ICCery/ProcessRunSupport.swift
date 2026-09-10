import Foundation

/// Shared hop for coalesced Argyll log batches (issue #80).
/// The runner invokes the sink off the main actor; this is the single hop back.
enum ProcessRunSupport {
    static func logSink(
        _ apply: @escaping @MainActor @Sendable ([String]) -> Void
    ) -> @Sendable ([String]) -> Void {
        { batch in
            Task { @MainActor in apply(batch) }
        }
    }

    @MainActor
    static func runLogged<T>(
        setRunning: (Bool) -> Void,
        resetLog: () -> Void,
        onLog: @escaping @MainActor @Sendable ([String]) -> Void,
        work: (@escaping @Sendable ([String]) -> Void) async throws -> T
    ) async throws -> T {
        setRunning(true)
        resetLog()
        defer { setRunning(false) }
        return try await work(logSink(onLog))
    }
}
