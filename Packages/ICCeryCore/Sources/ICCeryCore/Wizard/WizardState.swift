import Foundation

/// Session mode (docs/06 §wizardState). `"calibration"` is set while
/// Stage 0 is driving a `CAL_` chart through the same pipeline.
public enum SessionMode: String, Codable, Sendable {
    case profile
    case calibration
}

/// Persisted wizard state (docs/06 §wizardState fields) —
/// `wizard_state.json` in app data.
public struct WizardState: Codable, Equatable, Sendable {
    /// 0–5 (`WizardStage.rawValue`).
    public var currentStage: Int
    /// Run name without extension — never invented (#60).
    public var basename: String
    /// Working directory for artefacts; empty → `resolveSafeCwd` (#59).
    public var cwd: String
    /// Last spooled printer, for calibration drift history.
    public var printerName: String?
    public var sessionMode: SessionMode
    /// May differ from `basename` after a `.ti3` import (#94).
    public var profileBasename: String?
    /// The pre-`CAL_` basename, persisted so a crash/relaunch can
    /// restore the original (#29).
    public var calibrationOriginalBasename: String = ""

    private enum CodingKeys: String, CodingKey {
        case currentStage, basename, cwd, printerName, sessionMode
        case profileBasename, calibrationOriginalBasename
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.currentStage = try container.decodeIfPresent(Int.self, forKey: .currentStage)
            ?? WizardStage.generate.rawValue
        self.basename = try container.decodeIfPresent(String.self, forKey: .basename) ?? ""
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        self.printerName = try container.decodeIfPresent(String.self, forKey: .printerName)
        self.sessionMode = try container.decodeIfPresent(SessionMode.self, forKey: .sessionMode)
            ?? .profile
        self.profileBasename = try container.decodeIfPresent(String.self, forKey: .profileBasename)
        self.calibrationOriginalBasename = try container.decodeIfPresent(
            String.self, forKey: .calibrationOriginalBasename) ?? ""
    }

    public init(
        currentStage: Int = WizardStage.generate.rawValue,
        basename: String = "",
        cwd: String = "",
        printerName: String? = nil,
        sessionMode: SessionMode = .profile,
        profileBasename: String? = nil,
        calibrationOriginalBasename: String = ""
    ) {
        self.currentStage = currentStage
        self.basename = basename
        self.cwd = cwd
        self.printerName = printerName
        self.sessionMode = sessionMode
        self.profileBasename = profileBasename
        self.calibrationOriginalBasename = calibrationOriginalBasename
    }

    public static let `default` = WizardState()

    /// The stage a saved `currentStage` resolves to, clamped to a valid
    /// value (corrupt ints fall back to Stage 1).
    public var stage: WizardStage {
        WizardStage(rawValue: currentStage) ?? .generate
    }
}

/// Atomic JSON persistence for `WizardState` (issue #4).
public final class WizardStateStore: Sendable {
    public let fileURL: URL

    public init(
        fileURL: URL = AppPaths.appDataDir.appendingPathComponent("wizard_state.json")
    ) {
        self.fileURL = fileURL
    }

    public func load() -> WizardState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(WizardState.self, from: data)
        else { return .default }
        return state
    }

    public func save(_ state: WizardState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try AtomicFileWriter.write(encoder.encode(state), to: fileURL)
    }
}
