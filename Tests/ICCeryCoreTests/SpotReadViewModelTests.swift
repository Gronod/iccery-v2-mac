import Foundation
import XCTest
@testable import ICCeryCore
@testable import ICCery

/// Issue #148 — `SpotReadViewModel` under an isolated
/// `TestAppEnvironment` with per-test mock `spotread`/`instlist`
/// sidecars in a temp bin dir.
@MainActor
final class SpotReadViewModelTests: XCTestCase {

    private var env: TestAppEnvironment!
    private var workflow: TargetWorkflowViewModel!
    private var spot: SpotReadViewModel!
    private var binDir: URL!

    override func setUp() async throws {
        binDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spot-bin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: binDir, withIntermediateDirectories: true)
        // `bundledArgyllRoot` also points at the temp bin dir so the
        // real sidecars copied into the host app by the build phase do
        // not mask a missing `spotread` in the override dir.
        env = try TestAppEnvironment.make(
            argyllBinDir: binDir, bundledArgyllRoot: binDir)
        workflow = TargetWorkflowViewModel(environment: env.environment)
        spot = workflow.spotRead
        workflow.wizard.setTarget(basename: "spot", workingDirectory: env.root)
    }

    override func tearDown() async throws {
        spot?.stopIfNeeded()
        try? await Task.sleep(nanoseconds: 700_000_000)
        env?.cleanup()
        try? FileManager.default.removeItem(at: binDir)
        env = nil
        workflow = nil
        spot = nil
        binDir = nil
    }

    // MARK: - Helpers

    private func writeMock(_ name: String, _ body: String) throws {
        let url = binDir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func installInstlist(_ devicesJson: String) throws {
        try writeMock("instlist", """
            #!/bin/sh
            printf '%s' '\(devicesJson)'
            exit 0
            """)
    }

    private func installSpotread(lab: String = "51.9 -8.3 12.2") throws {
        try writeMock("spotread", """
            #!/bin/sh
            echo "Spot read needs a calibration before continuing"
            echo "Place instrument on spot reading white calibration tile,"
            echo " and then hit any key to continue,"
            echo "or hit Esc or Q to abort:"
            IFS= read -r line || exit 0
            echo "Calibration successful."
            while true; do
              echo "Place instrument on a spot to be measured,"
              echo " and hit a key to take a reading,"
              echo "or hit Esc or Q to abort:"
              IFS= read -r line || exit 0
              case "$line" in
                q*|Q*) exit 0 ;;
              esac
              echo "Result is XYZ: 18.51 20.05 15.71, D50 Lab: \(lab)"
            done
            """)
    }

    private func waitFor(
        _ predicate: @escaping () async -> Bool,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return await predicate()
    }

    private func waitForSync(
        _ predicate: @escaping () -> Bool,
        timeout: TimeInterval = 10
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    // MARK: - Missing sidecar

    func testMissingSidecarNoSpawn() async throws {
        // bin dir has no spotread → resolver override misses and the
        // bundled path does not exist either.
        XCTAssertFalse(spot.sidecarAvailable)
        spot.sheetOpened()
        XCTAssertEqual(workflow.wizard.notice?.kind, .error)

        spot.start()
        XCTAssertEqual(spot.lastError, "spotread sidecar missing — run fetch-argyll")
        XCTAssertFalse(spot.isRunning)
        let running = await env.environment.runner.processManager.isRunning(ProcessID.spotread)
        XCTAssertFalse(running)
    }

    // MARK: - defaultInstrument seeding

    func testDefaultInstrumentSeedsPicker() async throws {
        try installSpotread()
        try installInstlist("""
            {"event":"instruments","devices":[
              {"port":1,"name":"X-Rite i1Pro","type":"i1"},
              {"port":2,"name":"ColorMunki Photo","type":"CM"}]}
            """)
        var settings = env.environment.settingsStore.load()
        settings.defaultInstrument = "CM"
        try env.environment.settingsStore.save(settings)

        spot.sheetOpened()
        let ok1 = await waitFor { !self.spot.isDetecting && !self.spot.instruments.isEmpty }
        XCTAssertTrue(ok1)
        guard case .device(let device) = spot.selectedInstrument else {
            XCTFail("Expected device selection, got .auto")
            return
        }
        XCTAssertEqual(device.port, 2)
        XCTAssertFalse(spot.defaultMissing)
    }

    func testDefaultInstrumentNotPresent() async throws {
        try installSpotread()
        try installInstlist("""
            {"event":"instruments","devices":[
              {"port":1,"name":"X-Rite i1Pro","type":"i1"}]}
            """)
        var settings = env.environment.settingsStore.load()
        settings.defaultInstrument = "51"   // Spyder X — absent
        try env.environment.settingsStore.save(settings)

        spot.sheetOpened()
        let ok2 = await waitFor { !self.spot.isDetecting }
        XCTAssertTrue(ok2)
        XCTAssertEqual(spot.selectedInstrument, .auto)
        XCTAssertTrue(spot.defaultMissing)
    }

    func testSetDefaultToggleWritesSettingsOnly() async throws {
        try installSpotread()
        try installInstlist("""
            {"event":"instruments","devices":[
              {"port":2,"name":"ColorMunki Photo","type":"CM"}]}
            """)
        spot.sheetOpened()
        let ok3 = await waitFor { !self.spot.instruments.isEmpty }
        XCTAssertTrue(ok3)
        spot.selectedInstrument = .device(spot.instruments[0])
        spot.applyDefaultToggle(true)
        XCTAssertEqual(env.environment.settingsStore.load().defaultInstrument, "CM")
        // printtarg instrument is untouched (R15).
        XCTAssertEqual(workflow.instrument, .i1)
        spot.applyDefaultToggle(false)
        XCTAssertNil(env.environment.settingsStore.load().defaultInstrument)
    }

    // MARK: - Exclusive lease

    func testDuplicateSpotreadIdRejected() async throws {
        try writeMock("spotread", "#!/bin/sh\nsleep 30\n")
        let pm = env.environment.runner.processManager
        let bin = env.environment.runner.binaryResolver.resolve("spotread")
        try await pm.runStreaming(id: ProcessID.spotread, binary: bin, arguments: [])
        let ok4 = await pm.isRunning(ProcessID.spotread)
        XCTAssertTrue(ok4)
        do {
            try await pm.runStreaming(id: ProcessID.spotread, binary: bin, arguments: [])
            XCTFail("Expected duplicateID")
        } catch let error as ProcessError {
            guard case .duplicateID(let id) = error else {
                XCTFail("Expected duplicateID, got \(error)")
                return
            }
            XCTAssertEqual(id, "spotread")
        }
        await pm.kill(id: ProcessID.spotread)
    }

    // MARK: - Session

    func testMockSpotreadProducesSample() async throws {
        try installSpotread()
        spot.sheetOpened()
        spot.start()
        let ok5 = await waitFor { self.spot.state == .calibrating }
        XCTAssertTrue(ok5, "expected calibrating prompt")

        spot.calibrate()
        let ok6 = await waitFor { self.spot.state == .awaitingStrip }
        XCTAssertTrue(ok6, "expected read prompt")

        spot.trigger()
        let ok7 = await waitFor { !self.spot.samples.isEmpty }
        XCTAssertTrue(ok7, "expected a sample")
        let sample = try XCTUnwrap(spot.samples.first)
        XCTAssertEqual(sample.lab.l, 51.9, accuracy: 0.001)
        XCTAssertNotNil(sample.xyz)
        XCTAssertNil(spot.displayedDeltaE)   // first sample hides ΔE

        spot.trigger()
        let ok8 = await waitFor { self.spot.samples.count >= 2 }
        XCTAssertTrue(ok8, "expected a second sample")
        XCTAssertNotNil(spot.displayedDeltaE)
        XCTAssertEqual(spot.displayedDeltaE ?? -1, 0, accuracy: 0.0001)  // identical Lab

        spot.stopIfNeeded()
        XCTAssertFalse(spot.isRunning)
        let deadline = Date().addingTimeInterval(5)
        var alive = await env.environment.runner.processManager.isRunning(ProcessID.spotread)
        while alive && Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
            alive = await env.environment.runner.processManager.isRunning(ProcessID.spotread)
        }
        XCTAssertFalse(alive, "spotread child must not outlive Stop")
    }

    func testStartBlockedWhileChartreadRunning() async throws {
        try installSpotread()
        // Simulate a live Stage 3 chartread child.
        workflow.measurement.isChartreadRunning = true
        spot.sheetOpened()
        spot.start()
        XCTAssertEqual(spot.lastError, "Stop the Stage 3 chart read first.")
        XCTAssertFalse(spot.isRunning)
    }
}
