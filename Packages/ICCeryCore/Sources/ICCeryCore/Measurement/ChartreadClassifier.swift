import Foundation

/// Discrete states for the `chartread` interaction.
public enum ChartreadState: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case calibrating
    case awaitingStrip
    case reading
    case allStripsRead
    case warning
    case promptContinue
    case tablePlaceSheet
    case tableAlign
    case error
    case finished
}

/// Extra metadata produced by classifying a single `chartread` stdout line.
public struct ChartreadClassifyResult: Sendable, Equatable {
    public let state: ChartreadState
    /// Whether this line is an informational "remove last sheet" notice.
    public let isRemoveSheetNotice: Bool
    /// Parsed sheet index and total from "sheet N of M read ok" or "place sheet N of M".
    public let sheetNumber: Int?
    public let sheetTotal: Int?
    /// Fiducial patch name from XY "locate patch X with the sight".
    public let alignmentPatch: String?
    /// When a warning asks for a specific key (e.g. `y` or `n`), the caller should send that key.
    public let requestedWarningKey: String?
    /// Whether the line is a continuation of a multi-line XY prompt.
    public let isTableContinuation: Bool

    public init(
        state: ChartreadState,
        isRemoveSheetNotice: Bool = false,
        sheetNumber: Int? = nil,
        sheetTotal: Int? = nil,
        alignmentPatch: String? = nil,
        requestedWarningKey: String? = nil,
        isTableContinuation: Bool = false
    ) {
        self.state = state
        self.isRemoveSheetNotice = isRemoveSheetNotice
        self.sheetNumber = sheetNumber
        self.sheetTotal = sheetTotal
        self.alignmentPatch = alignmentPatch
        self.requestedWarningKey = requestedWarningKey
        self.isTableContinuation = isTableContinuation
    }
}

/// Pure line classifier for `chartread` stdout.
///
/// Matchers are evaluated in strict priority order (docs/04 §3.5, docs/05 §12.6).
/// XY table continuation lines stay sticky in `TABLE_PLACE_SHEET` / `TABLE_ALIGN`.
public enum ChartreadClassifier {

    private typealias Matcher = (String, ChartreadState) -> ChartreadClassifyResult?

    public static func classify(
        line: String,
        previousState: ChartreadState
    ) -> ChartreadClassifyResult {
        let text = line.lowercased()

        for matcher in matchers(previousState) {
            if let result = matcher(text, previousState) {
                return result
            }
        }

        return ChartreadClassifyResult(state: previousState)
    }

    private static func matchers(_ previous: ChartreadState) -> [Matcher] {
        [
            removeSheetNotice,
            sheetReadOk,
            locatePatch,
            placeSheet,
            continuation(previous),
            done,
            warning,
            calibration,
            awaitingStrip,
            reading,
            error
        ]
    }

    // 1. "Please remove last sheet from table" — info only.
    private static func removeSheetNotice(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        guard text.contains("remove") && text.contains("last") && text.contains("sheet") else { return nil }
        return ChartreadClassifyResult(state: previous, isRemoveSheetNotice: true)
    }

    // 2. "Sheet N of M read OK".
    private static func sheetReadOk(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        guard let match = text.firstMatch(pattern: #"sheet\s+(\d+)\s+of\s+(\d+)\s+read\s+ok"#) else { return nil }
        return ChartreadClassifyResult(
            state: previous,
            sheetNumber: match.1,
            sheetTotal: match.2
        )
    }

    // 3. "locate patch X with the sight".
    private static func locatePatch(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        guard let match = text.firstMatch(pattern: #"locate\s+patch\s+([a-z0-9_]+)\s+with"#),
              !match.0.isEmpty else { return nil }
        return ChartreadClassifyResult(
            state: .tableAlign,
            alignmentPatch: match.0.uppercased()
        )
    }

    // 4. "place sheet N of M" or "remove previous sheet".
    private static func placeSheet(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        if let match = text.firstMatch(pattern: #"place\s+sheet\s+(\d+)\s+of\s+(\d+)"#) {
            return ChartreadClassifyResult(
                state: .tablePlaceSheet,
                sheetNumber: match.1,
                sheetTotal: match.2
            )
        }
        if text.contains("remove previous sheet") || text.contains("place sheet") {
            return ChartreadClassifyResult(state: .tablePlaceSheet)
        }
        return nil
    }

    // 5. "hit return to continue" — sticky if already in a table state.
    private static func continuation(_ previous: ChartreadState) -> Matcher {
        return { text, _ in
            guard text.contains("hit return to continue")
                    || text.contains("hit any key to continue")
                    || text.contains("hit space to continue")
            else { return nil }

            if case .tablePlaceSheet = previous {
                return ChartreadClassifyResult(state: .tablePlaceSheet, isTableContinuation: true)
            }
            if case .tableAlign = previous {
                return ChartreadClassifyResult(state: .tableAlign, isTableContinuation: true)
            }

            return ChartreadClassifyResult(state: .promptContinue, isTableContinuation: true)
        }
    }

    // 6. Done / all read.
    private static func done(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let phrases = [
            "'d' if/when done", "d to finish/save", "all strips/patches read",
            "all strips read", "all patches read", "done reading",
            "'d' to save", "press d to", "hit 'd'"
        ]
        if phrases.contains(where: { text.contains($0) }) {
            return ChartreadClassifyResult(state: .allStripsRead)
        }
        return nil
    }

    // 7. Warnings / prompts needing a key.
    private static func warning(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let warningSignals = [
            "(warning)", "use it anyway", "seem to have read strip pass",
            "unexpected response", "seem to have read", "misread",
            "try again", "do you want to"
        ]
        guard warningSignals.contains(where: { text.contains($0) }) else { return nil }

        var key: String?
        if text.contains("(y/n)") || text.contains("'y' or 'n'") {
            // Default to asking the user; no automatic key.
            key = nil
        } else if text.contains("'y'") || text.contains("press y") || text.contains("hit 'y'") {
            key = "y"
        } else if text.contains("'n'") || text.contains("press n") || text.contains("hit 'n'") {
            key = "n"
        }

        return ChartreadClassifyResult(state: .warning, requestedWarningKey: key)
    }

    // 8. Calibration / place reference / white / standard tile.
    private static func calibration(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let lowercased = text.lowercased()
        let placeTokens = ["place", "reference", "white", "calibrat", "standard"]
        let hasPlaceSheet = lowercased.contains("place sheet") || lowercased.contains("remove previous sheet")
        let hasLocate = lowercased.contains("locate patch")

        guard placeTokens.contains(where: { lowercased.contains($0) }),
              !hasPlaceSheet,
              !hasLocate
        else { return nil }

        if lowercased.contains("hit any key to continue")
            || lowercased.contains("hit space to continue")
            || lowercased.contains("calibration")
            || lowercased.contains("calibrate")
            || lowercased.contains("white tile")
            || lowercased.contains("standard tile") {
            return ChartreadClassifyResult(state: .calibrating)
        }
        return nil
    }

    // 9. Awaiting strip.
    private static func awaitingStrip(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let lowercased = text.lowercased()
        let phrases = [
            "hit ... read ... strip", "ready to read", "read ... strip ... key",
            "hit any key to read", "ready to read strip", "hit a key to read",
            "press any key to read", "read strip"
        ]
        guard phrases.contains(where: { lowercased.contains($0) }) else { return nil }
        return ChartreadClassifyResult(state: .awaitingStrip)
    }

    // 10. Reading.
    private static func reading(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let lowercased = text.lowercased()
        let phrases = ["reading strip", "reading sheet", "processing", "scanning", "reading..."]
        guard phrases.contains(where: { lowercased.contains($0) }) else { return nil }
        return ChartreadClassifyResult(state: .reading)
    }

    // 11. Error.
    private static func error(text: String, previous: ChartreadState) -> ChartreadClassifyResult? {
        let phrases = ["error", "too fast", "too slow", "misread", "failed to read", "failed"]
        // Avoid false positives inside harmless words by matching full words where possible.
        let lower = text
        guard phrases.contains(where: { phrase in
            lower.contains(phrase) && !lower.contains("no error")
        }) else { return nil }

        if lower.contains("misread") || lower.contains("failed to read") || lower.contains("error") {
            return ChartreadClassifyResult(state: .error)
        }
        return nil
    }
}

private extension String {
    func firstMatch(pattern: String) -> (String, Int, Int)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: self, options: [], range: NSRange(self.startIndex..., in: self))
        else { return nil }

        let groups: [String] = (1..<match.numberOfRanges).compactMap { i in
            let r = match.range(at: i)
            guard r.location != NSNotFound, let range = Range(r, in: self) else { return nil }
            return String(self[range])
        }

        guard let first = groups.first else { return nil }
        let ints = groups.compactMap { Int($0) }
        let a = ints.count > 0 ? ints[0] : 0
        let b = ints.count > 1 ? ints[1] : 0
        return (first, a, b)
    }
}
