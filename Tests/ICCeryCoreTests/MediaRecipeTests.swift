import Foundation
import XCTest
@testable import ICCeryCore

/// Issue #146 — `MediaRecipe` Codable + validation contract.
final class MediaRecipeTests: XCTestCase {

    private func makeRecipe() -> MediaRecipe {
        MediaRecipe(
            id: "recipe-abc",
            name: "Epson Rag",
            notes: "notes",
            printerID: "epson_p900",
            printerDisplayName: "Epson SureColor P900",
            paperName: "Rag Photographique",
            driverMediaType: "PhotographicGlossy",
            inkSet: "PK",
            colourSpace: "rgb",
            presetID: "preset-std-rgb",
            calibrationURL: "/tmp/prof.cal",
            applyCalibration: true,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            updated: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    func testRoundTripSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(makeRecipe())
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        for key in [
            "printer_id", "printer_display_name", "paper_name",
            "driver_media_type", "ink_set", "colour_space", "preset_id",
            "calibration_url", "apply_calibration", "created", "updated",
            "id", "name", "notes",
        ] {
            XCTAssertNotNil(object[key], "missing key \(key)")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MediaRecipe.self, from: data)
        XCTAssertEqual(decoded, makeRecipe())
    }

    func testMissingRequiredKeyThrows() {
        for key in ["id", "name", "printer_id", "colour_space", "preset_id"] {
            var dict: [String: Any] = [
                "id": "r1", "name": "n", "printer_id": "q",
                "colour_space": "rgb", "preset_id": "p",
            ]
            dict.removeValue(forKey: key)
            let data = try! JSONSerialization.data(withJSONObject: dict)
            XCTAssertThrowsError(
                try JSONDecoder().decode(MediaRecipe.self, from: data),
                "expected throw without \(key)")
        }
    }

    func testUnknownKeysIgnored() throws {
        let dict: [String: Any] = [
            "id": "r1", "name": "n", "printer_id": "q",
            "colour_space": "rgb", "preset_id": "p",
            "future_field": "ignored",
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        let recipe = try JSONDecoder().decode(MediaRecipe.self, from: data)
        XCTAssertEqual(recipe.id, "r1")
        XCTAssertEqual(recipe.notes, "")
        XCTAssertFalse(recipe.applyCalibration)
    }

    func testValidatedGoldens() {
        var r = makeRecipe()

        r.name = "  "
        XCTAssertThrowsError(try r.validated()) {
            XCTAssertEqual($0 as? MediaRecipe.ValidationError, .emptyName)
        }

        r = makeRecipe()
        r.printerID = ""
        XCTAssertThrowsError(try r.validated()) {
            XCTAssertEqual($0 as? MediaRecipe.ValidationError, .emptyPrinterID)
        }

        r = makeRecipe()
        r.presetID = ""
        XCTAssertThrowsError(try r.validated()) {
            XCTAssertEqual($0 as? MediaRecipe.ValidationError, .emptyPresetID)
        }

        r = makeRecipe()
        r.colourSpace = "lab"
        XCTAssertThrowsError(try r.validated()) {
            XCTAssertEqual(
                $0 as? MediaRecipe.ValidationError, .invalidColourSpace("lab"))
        }

        for bad in ["../evil.cal", "rel/path.cal", "/tmp/a\0b.cal"] {
            r = makeRecipe()
            r.calibrationURL = bad
            XCTAssertThrowsError(try r.validated(), "expected throw for \(bad)") {
                XCTAssertEqual(
                    $0 as? MediaRecipe.ValidationError,
                    .invalidCalibrationURL(bad))
            }
        }
    }

    func testColourSpaceNormalisedToLowercase() throws {
        var r = makeRecipe()
        r.colourSpace = "RGB"
        let validated = try r.validated()
        XCTAssertEqual(validated.colourSpace, "rgb")
    }

    func testCalPrefixedCalNameIsSchemaValid() throws {
        var r = makeRecipe()
        // CAL_ refusal is an apply-time policy, not a schema error.
        r.calibrationURL = "/tmp/CAL_target.cal"
        XCTAssertNoThrow(try r.validated())
    }
}
