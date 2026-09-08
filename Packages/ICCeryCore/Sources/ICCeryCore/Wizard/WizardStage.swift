import Foundation

/// The five wizard stages plus Stage 0 (calibration), matching the v1
/// `data-stage` contract in docs/21. Stepper buttons 1–5 map to
/// `.generate` … `.verifyInstall`; `.calibrate` lives outside the stepper.
public enum WizardStage: Int, CaseIterable, Sendable, Codable {
    case calibrate = 0
    case generate = 1
    case layOutPrint = 2
    case measure = 3
    case buildProfile = 4
    case verifyInstall = 5

    /// Sidebar stepper position (1–5); `nil` for the out-of-band calibrate stage.
    public var stepperIndex: Int? {
        self == .calibrate ? nil : rawValue
    }

    public var title: String {
        switch self {
        case .calibrate:     return "Printer Calibration"
        case .generate:      return "Generate Target"
        case .layOutPrint:   return "Lay Out & Print"
        case .measure:       return "Measure Chart"
        case .buildProfile:  return "Build Profile"
        case .verifyInstall: return "Verify & Install"
        }
    }

    public var symbolName: String {
        switch self {
        case .calibrate:     return "slider.horizontal.3"
        case .generate:      return "square.grid.3x3"
        case .layOutPrint:   return "printer"
        case .measure:       return "eyedropper.halffull"
        case .buildProfile:  return "paintpalette"
        case .verifyInstall: return "checkmark.seal"
        }
    }

    /// Stages shown in the sidebar stepper, in order.
    public static var stepperStages: [WizardStage] {
        [.generate, .layOutPrint, .measure, .buildProfile, .verifyInstall]
    }
}
