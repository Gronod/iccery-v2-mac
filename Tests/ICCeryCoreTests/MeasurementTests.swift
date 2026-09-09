import Foundation
import Testing
@testable import ICCeryCore

@Suite("InstrumentParser")
struct InstrumentParserTests {

    @Test("Parses pretty-printed instlist JSON")
    func json() throws {
        let json = """
        {
          "event": "instruments",
          "devices": [
            {"port": 1, "name": "X-Rite i1Pro", "type": "usb"},
            {"port": 2, "name": "i1Pro 2", "type": "usb"},
            {"port": 3, "name": "i1iO Table", "type": "usb"}
          ]
        }
        """
        let devices = try InstrumentParser.parse(json)
        #expect(devices.count == 3)
        #expect(devices[0].port == 1)
        #expect(devices[0].name == "X-Rite i1Pro")
        #expect(devices[2].port == 3)
    }

    @Test("Falls back to regex for legacy instlist text")
    func regexFallback() throws {
        let text = """
        1: 'X-Rite i1Pro' on usb
        2: 'ColorMunki Smile'
        """ + "\n"
        let devices = try InstrumentParser.parse(text)
        #expect(devices.count == 2)
        #expect(devices[0].port == 1)
        #expect(devices[1].name == "ColorMunki Smile")
    }

    @Test("Empty output returns no devices")
    func empty() throws {
        #expect(try InstrumentParser.parse("").isEmpty)
    }
}

@Suite("ChartreadArgs")
struct ChartreadArgsTests {

    @Test("Baseline argv and port 1 omits -c")
    func baseline() throws {
        let config = ChartreadConfig(basename: "target", selectedPort: 1)
        let args = try ChartreadArgs.build(config: config)
        #expect(args == ["-v", "-u", "target"])
    }

    @Test("Port > 1 emits -c")
    func portArgument() throws {
        let config = ChartreadConfig(basename: "target", selectedPort: 3)
        let args = try ChartreadArgs.build(config: config)
        #expect(args == ["-v", "-u", "-c", "3", "target"])
    }

    @Test("LEDs emit -Y l")
    func leds() throws {
        let config = ChartreadConfig(
            basename: "target",
            selectedPort: 2,
            enableLEDs: true
        )
        let args = try ChartreadArgs.build(config: config)
        #expect(args.contains("-Y"))
        #expect(args.contains("l"))
    }

    @Test("Auto omits -c")
    func autoPort() throws {
        let config = ChartreadConfig(basename: "target")
        let args = try ChartreadArgs.build(config: config)
        #expect(!args.contains("-c"))
    }
}

@Suite("ChartreadClassifier")
struct ChartreadClassifierTests {

    @Test("Calibration prompt")
    func calibration() {
        let r = ChartreadClassifier.classify(
            line: "Place instrument on calibration tile and hit [Space] to calibrate.",
            previousState: .idle
        )
        #expect(r.state == .calibrating)
    }

    @Test("Strip awaiting")
    func awaitingStrip() {
        let r = ChartreadClassifier.classify(
            line: "Hit [Space] to read strip A",
            previousState: .calibrating
        )
        #expect(r.state == .awaitingStrip)
    }

    @Test("Done prompt")
    func done() {
        let r = ChartreadClassifier.classify(
            line: "'d' if/when done",
            previousState: .awaitingStrip
        )
        #expect(r.state == .allStripsRead)
    }

    @Test("XY place sheet")
    func placeSheet() {
        let r = ChartreadClassifier.classify(
            line: "Please place sheet 1 of 2 on the table",
            previousState: .idle
        )
        #expect(r.state == .tablePlaceSheet)
        #expect(r.sheetNumber == 1)
        #expect(r.sheetTotal == 2)
    }

    @Test("XY locate patch")
    func locatePatch() {
        let r = ChartreadClassifier.classify(
            line: "locate patch A1 with the sight,",
            previousState: .tablePlaceSheet
        )
        #expect(r.state == .tableAlign)
        #expect(r.alignmentPatch == "A1")
    }

    @Test("Remove sheet notice preserves state")
    func removeNotice() {
        let r = ChartreadClassifier.classify(
            line: "Please remove last sheet from table",
            previousState: .tablePlaceSheet
        )
        #expect(r.state == .tablePlaceSheet)
        #expect(r.isRemoveSheetNotice == true)
    }
}

@Suite("ChartreadRow")
struct ChartreadRowTests {

    @Test("Decodes row JSON")
    func decode() throws {
        let json = """
        {"event": "row_complete", "row_id": "A", "row_index": 0, "total_rows": 2,
         "patch_count": 1, "patches": [
           {"id": "1", "loc": "A1", "is_pad": false, "device": [0, 50, 100],
            "expected": {"Lab": [50, 0, 0]},
            "measured": {"Lab": [51, 1, -1]}}
         ]}
        """
        let row = try JSONDecoder().decode(ChartreadRow.self, from: Data(json.utf8))
        #expect(row.rowId == "A")
        #expect(row.patchCount == 1)
        #expect(row.patches[0].measured.lab?.l == 51)
    }
}

@Suite("ColourMath")
struct ColourMathTests {

    @Test("White XYZ to Lab")
    func whiteLab() {
        let white = XYZColor(x: 96.4212, y: 100.0, z: 82.5188)
        let lab = LabColorMath.xyzToLab(white)
        #expect(abs(lab.l - 100) < 0.5)
        #expect(abs(lab.a) < 0.5)
        #expect(abs(lab.b) < 0.5)
    }

    @Test("Lab to sRGB roundtrip is clamped")
    func labToSRGB() {
        let red = LabColor(l: 55, a: 80, b: 70)
        let rgb = LabColorMath.labToSRGB(red)
        #expect(rgb.r > 0.8)
        #expect(rgb.g < 0.2)
        #expect(rgb.b < 0.2)
    }

    @Test("Pad white returns DisplayRGB")
    func padWhite() {
        let white = LabColor(l: 95, a: 0, b: 0)
        let rgb = LabColorMath.labToSRGB(white)
        #expect(rgb.r > 0.9)
        #expect(rgb.g > 0.9)
        #expect(rgb.b > 0.9)
    }

    @Test("Standard CIEDE2000 vector (Sharma)")
    func ciede2000() {
        let a = LabColor(l: 50, a: -1.3802, b: -84.2814)
        let b = LabColor(l: 50, a: 0.0000, b: -82.7485)
        #expect(abs(ColorDifference.deltaE00(a, b) - 1.00) < 0.001)
    }

    @Test("Classification respects thresholds")
    func classify() {
        #expect(ColorDifference.classify(deltaE: 0.5, goodMax: 2.0, warningMax: 5.0) == .good)
        #expect(ColorDifference.classify(deltaE: 3.0, goodMax: 2.0, warningMax: 5.0) == .warning)
        #expect(ColorDifference.classify(deltaE: 6.0, goodMax: 2.0, warningMax: 5.0) == .bad)
    }
}

@Suite("MeasurementArtefacts")
struct MeasurementArtefactTests {

    private func makeCwd() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Discovers passes in order")
    func discovery() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        try "A".write(to: cwd.appendingPathComponent("target_pass3.ti3"), atomically: true, encoding: .utf8)
        try "B".write(to: cwd.appendingPathComponent("target_pass1.ti3"), atomically: true, encoding: .utf8)
        try "C".write(to: cwd.appendingPathComponent("target_pass10.ti3"), atomically: true, encoding: .utf8)

        let passes = MeasurementArtefacts.passSnapshots(basename: "target", cwd: cwd)
        #expect(passes.map(\.lastPathComponent) == ["target_pass1.ti3", "target_pass3.ti3", "target_pass10.ti3"])
    }

    @Test("Snapshot and promote are atomic")
    func snapshotPromote() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let canonical = cwd.appendingPathComponent("target.ti3")
        try "canonical".write(to: canonical, atomically: true, encoding: .utf8)

        let pass = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)
        #expect(pass.lastPathComponent == "target_pass1.ti3")
        #expect(!FileManager.default.fileExists(atPath: canonical.path))

        let promoted = try MeasurementArtefacts.promotePass(pass: pass, basename: "target", cwd: cwd)
        #expect(promoted.lastPathComponent == "target.ti3")
        #expect(FileManager.default.fileExists(atPath: promoted.path))
    }

    @Test("Pass collisions handled")
    func collision() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let canonical = cwd.appendingPathComponent("target.ti3")
        try "v1".write(to: canonical, atomically: true, encoding: .utf8)
        _ = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)

        try "v2".write(to: canonical, atomically: true, encoding: .utf8)
        let pass2 = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)
        #expect(pass2.lastPathComponent == "target_pass2.ti3")
    }
}

@Suite("AverageArgs")
struct AverageArgsTests {

    @Test("Requires at least two pass files")
    func passCount() {
        let cwd = URL(fileURLWithPath: "/tmp")
        let config = AverageConfig(
            workingDirectory: cwd,
            basename: "target",
            passFiles: [URL(fileURLWithPath: "target_pass1.ti3")]
        )
        #expect(throws: AverageArgError.self) {
            _ = try AverageArgs.build(config: config)
        }
    }

    @Test("Output is last and inputs are relative")
    func ordering() throws {
        let cwd = URL(fileURLWithPath: "/tmp")
        let config = AverageConfig(
            workingDirectory: cwd,
            basename: "target",
            passFiles: [
                URL(fileURLWithPath: "/tmp/target_pass1.ti3"),
                URL(fileURLWithPath: "/tmp/target_pass2.ti3"),
            ]
        )
        let args = try AverageArgs.build(config: config)
        #expect(args.first == "-v")
        #expect(args.last == "target.ti3")
        #expect(args == ["-v", "target_pass1.ti3", "target_pass2.ti3", "target.ti3"])
    }
}
