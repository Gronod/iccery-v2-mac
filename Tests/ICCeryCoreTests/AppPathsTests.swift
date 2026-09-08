import Testing
import Foundation
@testable import ICCeryCore

@Suite("AppPaths")
struct AppPathsTests {
    @Test func appDataDirUsesBundleID() {
        #expect(AppPaths.appDataDir.path.contains("Library/Application Support/com.gronod.iccery2"))
    }

    @Test func logFileIsUnderLibraryLogs() {
        #expect(AppPaths.logFile.lastPathComponent == "iccery.log")
        #expect(AppPaths.logFile.path.contains("Library/Logs/com.gronod.iccery2"))
    }

    @Test func bundledArgyllDirIsInsideResources() {
        #expect(AppPaths.bundledArgyllDir.lastPathComponent == "Argyll")
    }
}

@Suite("WizardStage")
struct WizardStageTests {
    @Test func stepperOrderIsOneThroughFive() {
        #expect(WizardStage.stepperStages.map(\.stepperIndex) == [1, 2, 3, 4, 5])
        #expect(WizardStage.calibrate.stepperIndex == nil)
    }
}
