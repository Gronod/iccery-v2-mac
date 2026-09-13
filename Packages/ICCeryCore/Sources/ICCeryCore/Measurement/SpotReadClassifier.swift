import Foundation

/// Line classifier for `spotread` stdout (issue #148).
///
/// `spotread` shares `chartread`'s white-tile calibration phrasing, so
/// this wraps `ChartreadClassifier` and only intercepts the lines that
/// would otherwise misclassify:
///
/// - `… and then hit any key to continue,` / `or hit Esc or Q to abort:`
///   continuation lines that trail the calibration and spot prompts —
///   sticky to the current prompt state instead of `PROMPT_CONTINUE`.
/// - `Place instrument on a spot to be measured,` /
///   `and hit a key to take a reading,` → `AWAITING_STRIP` (the Read
///   prompt; the generic chartread matcher does not know "take a
///   reading").
///
/// Sample lines (`Result is XYZ: …, D50 Lab: …`) are parsed by
/// `SpotReadParser`, not classified here.
public enum SpotReadClassifier {

    public static func classify(
        line: String,
        previousState: ChartreadState
    ) -> ChartreadClassifyResult {
        let text = line.lowercased()

        // Spot-read prompt continuations keep the current prompt state.
        if previousState == .calibrating || previousState == .awaitingStrip {
            if text.contains("hit any key")
                || text.contains("hit space")
                || text.contains("esc or")
                || text.contains("abort")
                || text.contains("to abort") {
                return ChartreadClassifyResult(state: previousState)
            }
        }

        // "Place instrument on a spot to be measured," /
        // " and hit a key to take a reading," — the Read trigger prompt.
        if text.contains("spot to be measured")
            || text.contains("take a reading")
            || text.contains("measure the spot") {
            return ChartreadClassifyResult(state: .awaitingStrip)
        }

        return ChartreadClassifier.classify(line: line, previousState: previousState)
    }
}
