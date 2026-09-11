import Foundation
import XCTest
@testable import ICCeryCore

final class InstrumentParserTests: XCTestCase {

    func testJson() throws {
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
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].port, 1)
        XCTAssertEqual(devices[0].name, "X-Rite i1Pro")
        XCTAssertEqual(devices[2].port, 3)
    }

    func testRegexFallback() throws {
        let text = """
        1: 'X-Rite i1Pro' on usb
        2: 'ColorMunki Smile'
        """ + "\n"
        let devices = try InstrumentParser.parse(text)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices[0].port, 1)
        XCTAssertEqual(devices[1].name, "ColorMunki Smile")
    }

    func testEmpty() throws {
        XCTAssertTrue(try InstrumentParser.parse("").isEmpty)
    }
}

final class ChartreadArgsTests: XCTestCase {

    func testBaseline() throws {
        let config = ChartreadConfig(basename: "target", selectedPort: 1)
        let args = try ChartreadArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-u", "target"])
    }

    func testPortArgument() throws {
        let config = ChartreadConfig(basename: "target", selectedPort: 3)
        let args = try ChartreadArgs.build(config: config)
        XCTAssertEqual(args, ["-v", "-u", "-c", "3", "target"])
    }

    func testLeds() throws {
        let config = ChartreadConfig(
            basename: "target",
            selectedPort: 2,
            enableLEDs: true
        )
        let args = try ChartreadArgs.build(config: config)
        XCTAssertTrue(args.contains("-Y"))
        XCTAssertTrue(args.contains("l"))
    }

    func testAutoPort() throws {
        let config = ChartreadConfig(basename: "target")
        let args = try ChartreadArgs.build(config: config)
        XCTAssertFalse(args.contains("-c"))
    }
}

final class ChartreadClassifierTests: XCTestCase {

    func testCalibration() {
        let r = ChartreadClassifier.classify(
            line: "Place instrument on calibration tile and hit [Space] to calibrate.",
            previousState: .idle
        )
        XCTAssertEqual(r.state, .calibrating)
    }

    func testAwaitingStrip() {
        let r = ChartreadClassifier.classify(
            line: "Hit [Space] to read strip A",
            previousState: .calibrating
        )
        XCTAssertEqual(r.state, .awaitingStrip)
    }

    func testDone() {
        let r = ChartreadClassifier.classify(
            line: "'d' if/when done",
            previousState: .awaitingStrip
        )
        XCTAssertEqual(r.state, .allStripsRead)
    }

    func testPlaceSheet() {
        let r = ChartreadClassifier.classify(
            line: "Please place sheet 1 of 2 on the table",
            previousState: .idle
        )
        XCTAssertEqual(r.state, .tablePlaceSheet)
        XCTAssertEqual(r.sheetNumber, 1)
        XCTAssertEqual(r.sheetTotal, 2)
    }

    func testLocatePatch() {
        let r = ChartreadClassifier.classify(
            line: "locate patch A1 with the sight,",
            previousState: .tablePlaceSheet
        )
        XCTAssertEqual(r.state, .tableAlign)
        XCTAssertEqual(r.alignmentPatch, "A1")
    }

    func testRemoveNotice() {
        let r = ChartreadClassifier.classify(
            line: "Please remove last sheet from table",
            previousState: .tablePlaceSheet
        )
        XCTAssertEqual(r.state, .tablePlaceSheet)
        XCTAssertEqual(r.isRemoveSheetNotice, true)
    }
}

final class ChartreadRowTests: XCTestCase {

    func testDecode() throws {
        let json = """
        {"event": "row_complete", "row_id": "A", "row_index": 0, "total_rows": 2,
         "patch_count": 1, "patches": [
           {"id": "1", "loc": "A1", "is_pad": false, "device": [0, 50, 100],
            "expected": {"Lab": [50, 0, 0]},
            "measured": {"Lab": [51, 1, -1]}}
         ]}
        """
        let row = try JSONDecoder().decode(ChartreadRow.self, from: Data(json.utf8))
        XCTAssertEqual(row.rowId, "A")
        XCTAssertEqual(row.patchCount, 1)
        XCTAssertEqual(row.patches[0].measured.lab?.l, 51)
    }

    func testDecodeXYZAndLab() throws {
        let json = """
        {"event": "row_complete", "row_id": "B", "row_index": 1, "total_rows": 2,
         "patch_count": 1, "patches": [
           {"id": "7", "loc": "B7", "is_pad": false, "device": [10, 20, 30, 40],
            "measured": {"XYZ": [30.5, 32.1, 25.9], "Lab": [63.4, 2.5, -8.2]}}
         ]}
        """
        let row = try JSONDecoder().decode(ChartreadRow.self, from: Data(json.utf8))
        let measured = row.patches[0].measured
        XCTAssertEqual(measured.xyz, CIEXYZ(x: 30.5, y: 32.1, z: 25.9))
        XCTAssertEqual(measured.lab, CIELab(l: 63.4, a: 2.5, b: -8.2))
    }

    func testXyzWireEncoding() throws {
        for color in [XYZColor(x: 1.5, y: 2.5, z: 3.5), CIEXYZ(x: 1.5, y: 2.5, z: 3.5)] {
            let value = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(color))
            XCTAssertEqual(value as? [Double], [1.5, 2.5, 3.5])
        }
    }

    func testLabWireEncoding() throws {
        for color in [LabColor(l: 50, a: -1, b: 2), CIELab(l: 50, a: -1, b: 2)] {
            let value = try JSONSerialization.jsonObject(
                with: JSONEncoder().encode(color))
            XCTAssertEqual(value as? [Double], [50, -1, 2])
        }
    }

    func testPatchColorKeys() throws {
        let color = PatchColor(
            xyz: CIEXYZ(x: 10, y: 20, z: 30),
            lab: CIELab(l: 55, a: 1, b: -2))
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(color)) as? [String: Any]
        XCTAssertEqual(object?["XYZ"] as? [Double], [10, 20, 30])
        XCTAssertEqual(object?["Lab"] as? [Double], [55, 1, -2])
        XCTAssertNil(object?["spectral"])
    }
}

final class ColourMathTests: XCTestCase {

    func testWhiteLab() {
        let white = XYZColor(x: 96.4212, y: 100.0, z: 82.5188)
        let lab = LabColorMath.xyzToLab(white)
        XCTAssertTrue(abs(lab.l - 100) < 0.5)
        XCTAssertTrue(abs(lab.a) < 0.5)
        XCTAssertTrue(abs(lab.b) < 0.5)
    }

    func testLabToSRGB() {
        let red = LabColor(l: 55, a: 80, b: 70)
        let rgb = LabColorMath.labToSRGB(red)
        XCTAssertTrue(rgb.r > 0.8)
        XCTAssertTrue(rgb.g < 0.2)
        XCTAssertTrue(rgb.b < 0.2)
    }

    func testPadWhite() {
        let white = LabColor(l: 95, a: 0, b: 0)
        let rgb = LabColorMath.labToSRGB(white)
        XCTAssertTrue(rgb.r > 0.9)
        XCTAssertTrue(rgb.g > 0.9)
        XCTAssertTrue(rgb.b > 0.9)
    }

    func testCiede2000() {
        let a = LabColor(l: 50, a: -1.3802, b: -84.2814)
        let b = LabColor(l: 50, a: 0.0000, b: -82.7485)
        XCTAssertTrue(abs(ColorDifference.deltaE00(a, b) - 1.00) < 0.001)
    }

    func testClassify() {
        XCTAssertEqual(ColorDifference.classify(deltaE: 0.5, goodMax: 2.0, warningMax: 5.0), .good)
        XCTAssertEqual(ColorDifference.classify(deltaE: 3.0, goodMax: 2.0, warningMax: 5.0), .warning)
        XCTAssertEqual(ColorDifference.classify(deltaE: 6.0, goodMax: 2.0, warningMax: 5.0), .bad)
    }
}

final class MeasurementArtefactTests: XCTestCase {

    private func makeCwd() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testDiscovery() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        try "A".write(to: cwd.appendingPathComponent("target_pass3.ti3"), atomically: true, encoding: .utf8)
        try "B".write(to: cwd.appendingPathComponent("target_pass1.ti3"), atomically: true, encoding: .utf8)
        try "C".write(to: cwd.appendingPathComponent("target_pass10.ti3"), atomically: true, encoding: .utf8)

        let passes = MeasurementArtefacts.passSnapshots(basename: "target", cwd: cwd)
        XCTAssertEqual(passes.map(\.lastPathComponent), ["target_pass1.ti3", "target_pass3.ti3", "target_pass10.ti3"])
    }

    func testSnapshotPromote() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let canonical = cwd.appendingPathComponent("target.ti3")
        try "canonical".write(to: canonical, atomically: true, encoding: .utf8)

        let pass = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)
        XCTAssertEqual(pass.lastPathComponent, "target_pass1.ti3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: canonical.path))

        let promoted = try MeasurementArtefacts.promotePass(pass: pass, basename: "target", cwd: cwd)
        XCTAssertEqual(promoted.lastPathComponent, "target.ti3")
        XCTAssertTrue(FileManager.default.fileExists(atPath: promoted.path))
    }

    func testCollision() throws {
        let cwd = try makeCwd()
        defer { try? FileManager.default.removeItem(at: cwd) }

        let canonical = cwd.appendingPathComponent("target.ti3")
        try "v1".write(to: canonical, atomically: true, encoding: .utf8)
        _ = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)

        try "v2".write(to: canonical, atomically: true, encoding: .utf8)
        let pass2 = try MeasurementArtefacts.snapshotPass(basename: "target", cwd: cwd)
        XCTAssertEqual(pass2.lastPathComponent, "target_pass2.ti3")
    }
}

final class AverageArgsTests: XCTestCase {

    func testPassCount() {
        let cwd = URL(fileURLWithPath: "/tmp")
        let config = AverageConfig(
            workingDirectory: cwd,
            basename: "target",
            passFiles: [URL(fileURLWithPath: "target_pass1.ti3")]
        )
        XCTAssertThrowsError(try AverageArgs.build(config: config)) { error in
            XCTAssertTrue(error is AverageArgError)
        }
    }

    func testOrdering() throws {
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
        XCTAssertEqual(args.first, "-v")
        XCTAssertEqual(args.last, "target.ti3")
        XCTAssertEqual(args, ["-v", "target_pass1.ti3", "target_pass2.ti3", "target.ti3"])
    }
}
