import Foundation
import Observation
import SwiftUI
import ICCeryCore

/// Stage 0 calibration workflow: generate wedge, print, measure, and
/// compute `.cal` curves.
@MainActor
@Observable
final class CalibrationViewModel {

    let workflow: TargetWorkflowViewModel
    let profile: ProfileWorkflowViewModel
    let environment: AppEnvironment

    // MARK: - Form state

    var colourSpace: ColourSpace = .cmyk
    var steps: Int = 21
    var whitePatches: Int = 4
    var includeNeutralEmphasis: Bool = false
    var inkLimit: String = "320"
    var applyToProfile: Bool = false
    var computedCalURL: URL?
    var calibrationLog: [String] = []
    var isGenerating = false
    var isComputing = false
    var lastError: String?

    init(workflow: TargetWorkflowViewModel, profile: ProfileWorkflowViewModel, environment: AppEnvironment) {
        self.workflow = workflow
        self.profile = profile
        self.environment = environment
    }

    private var wizard: WizardViewModel { workflow.wizard }

    // MARK: - Derived

    var canGenerate: Bool {
        !wizard.basename.isEmpty && wizard.effectiveWorkingDirectory != nil && !isGenerating
    }

    var canCompute: Bool {
        calibrationTi3URL != nil && !isComputing
    }

    var calibrationTi3URL: URL? {
        guard let cwd = wizard.effectiveWorkingDirectory else { return nil }
        return cwd.appendingPathComponent("\(calBasename).ti3")
    }

    private var calBasename: String {
        if wizard.basename.hasPrefix("CAL_") { return wizard.basename }
        let original = !wizard.calibrationOriginalBasename.isEmpty
            ? wizard.calibrationOriginalBasename
            : wizard.basename
        return "CAL_\(original)"
    }

    private var calOutputURL: URL? {
        guard let cwd = wizard.effectiveWorkingDirectory else { return nil }
        return cwd.appendingPathComponent("\(calBasename).cal")
    }

    // MARK: - Generate calibration target

    func generateTarget() {
        guard canGenerate, let cwd = wizard.effectiveWorkingDirectory else { return }
        // Snapshot the original (pre-CAL_) basename before changing the live one.
        if !wizard.basename.hasPrefix("CAL_") {
            wizard.calibrationOriginalBasename = wizard.basename
        } else if wizard.calibrationOriginalBasename.isEmpty {
            wizard.calibrationOriginalBasename = String(wizard.basename.dropFirst(4))
        }
        let original = wizard.calibrationOriginalBasename
        wizard.basename = "CAL_\(original)"
        wizard.sessionMode = .calibration

        isGenerating = true
        calibrationLog = []
        lastError = nil

        let config = CalibrationTargenConfig(
            colourSpace: colourSpace,
            steps: steps,
            whitePatches: whitePatches,
            includeNeutralEmphasis: includeNeutralEmphasis,
            inkLimit: inkLimitValue,
            basename: original,
            workingDirectory: cwd
        )

        Task { @MainActor in
            defer { self.isGenerating = false }

            do {
                _ = try await self.environment.runner.runCalibrationTargen(config: config) { batch in
                    Task { @MainActor [weak self] in
                        self?.calibrationLog.append(contentsOf: batch)
                    }
                }
                self.wizard.refreshGating()
                self.wizard.showNotice("Calibration target generated.")
                self.wizard.go(to: .layOutPrint)
            } catch {
                self.lastError = error.localizedDescription
                self.wizard.showNotice(
                    "Calibration target failed: \(error.localizedDescription)",
                    kind: .error
                )
                self.wizard.restoreCalibration()
            }
        }
    }

    // MARK: - Layout, print, measure

    /// Hand off to the normal Stage 2/3 machinery using the `CAL_` basename.
    /// After measurement, the user returns and presses Compute Curves.
    func createLayout() {
        wizard.sessionMode = .calibration
        wizard.go(to: .layOutPrint)
    }

    func measureChart() {
        wizard.sessionMode = .calibration
        wizard.go(to: .measure)
    }

    // MARK: - Compute curves

    func computeCurves() {
        guard canCompute,
              let cwd = wizard.effectiveWorkingDirectory,
              let outputURL = calOutputURL else { return }

        // Collision check: the Argyll `printcal` exit error contains
        // "already exists" when the user declines overwrite. We do not
        // silently clobber.
        if FileManager.default.fileExists(atPath: outputURL.path) {
            lastError = "\(outputURL.lastPathComponent) already exists. Rename or overwrite it first."
            wizard.showNotice(lastError!, kind: .error)
            return
        }

        isComputing = true
        calibrationLog = []
        lastError = nil

        let config = PrintcalConfig(
            ti3Basename: calBasename,
            workingDirectory: cwd,
            outputURL: outputURL,
            noInkLimit: false,
            verify: false,
            previousCalPath: nil,
            totalInkLimit: inkLimitValue.map { Double($0) },
            channelLimits: []
        )

        Task { @MainActor in
            defer { self.isComputing = false }

            do {
                let url = try await self.environment.runner.runPrintcal(config: config) { batch in
                    Task { @MainActor [weak self] in
                        self?.calibrationLog.append(contentsOf: batch)
                    }
                }
                self.computedCalURL = url
                self.profile.calibrationFile = url.path
                self.profile.applyCalibration = self.applyToProfile
                self.wizard.showNotice("Calibration curves computed.")
                self.wizard.restoreCalibration()
            } catch {
                self.lastError = error.localizedDescription
                self.wizard.showNotice(
                    "Calibration curve computation failed: \(error.localizedDescription)",
                    kind: .error
                )
            }
        }
    }

    // MARK: - Apply toggle

    func updateApplyToProfile() {
        profile.applyCalibration = applyToProfile
        if applyToProfile, let url = computedCalURL {
            profile.calibrationFile = url.path
        } else if applyToProfile {
            // User toggled on before computing; keep the path if already set.
        } else {
            profile.applyCalibration = false
        }
    }

    func returnToProfiling() {
        wizard.restoreCalibration()
        wizard.go(to: .generate)
    }

    private var inkLimitValue: Int? {
        guard colourSpace == .cmyk else { return nil }
        return Int(inkLimit)
    }
}
