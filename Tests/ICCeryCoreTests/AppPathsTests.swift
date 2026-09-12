import XCTest
import Foundation
@testable import ICCeryCore

final class AppPathsTests: XCTestCase {
    func testAppDataDirUsesBundleID() {
        XCTAssertTrue(AppPaths.appDataDir.path.contains("Library/Application Support/com.gronod.iccery2"))
    }

    func testLogFileIsUnderLibraryLogs() {
        XCTAssertEqual(AppPaths.logFile.lastPathComponent, "iccery.log")
        XCTAssertTrue(AppPaths.logFile.path.contains("Library/Logs/com.gronod.iccery2"))
    }

    func testBundledArgyllDirIsInsideResources() {
        XCTAssertEqual(AppPaths.bundledArgyllDir.lastPathComponent, "Argyll")
    }
}

final class WizardStageTests: XCTestCase {
    func testStepperOrderIsOneThroughFive() {
        XCTAssertEqual(WizardStage.stepperStages.map(\.stepperIndex), [1, 2, 3, 4, 5])
        XCTAssertNil(WizardStage.calibrate.stepperIndex)
    }
}
