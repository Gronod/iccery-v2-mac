import Foundation
import Observation
import ICCeryCore

/// Wizard shell state (issue #1). Artefact gating, persistence and the
/// "open existing" flow land in issue #4.
@MainActor
@Observable
final class WizardViewModel {
    /// Currently displayed stage.
    var stage: WizardStage = .generate

    /// Banner notice currently displayed (`#wizardNotification`).
    var notice: Notice?

    /// Target basename shared across stages (`targetBasename`).
    var basename: String = ""

    /// Working directory for all Argyll artefacts.
    var workingDirectory: URL?

    /// Printer queue selected in Stage 2; retained across stages.
    var printerName: String?

    private var noticeDismissTask: Task<Void, Never>?

    /// `true` while Stage 0 (printer calibration) is shown instead of a
    /// stepper stage.
    var isCalibrating: Bool { stage == .calibrate }

    func go(to stage: WizardStage) {
        self.stage = stage
    }

    func enterCalibration() {
        stage = .calibrate
    }

    func exitCalibration() {
        stage = .generate
    }

    func showNotice(_ text: String, kind: Notice.Kind = .info, autoHideAfter: TimeInterval? = 6) {
        noticeDismissTask?.cancel()
        let notice = Notice(kind: kind, text: text, autoHideAfter: autoHideAfter)
        self.notice = notice
        if let delay = notice.autoHideAfter {
            noticeDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if self?.notice?.id == notice.id {
                    self?.notice = nil
                }
            }
        }
    }

    func dismissNotice() {
        noticeDismissTask?.cancel()
        notice = nil
    }
}
