import AppKit
import Foundation
import XCTest
@testable import ICCery

/// Issue #201 Phase 2 — `PMTicketBridge.serialise`/`restore` byte
/// round-trip, cross-queue refusal (R3), plist fallback, and the
/// `takeRetainedValue` ownership canary.
@MainActor
final class PrintTicketTests: XCTestCase {

    /// The queue a destination `NSPrintInfo` will report as bound —
    /// the session's current printer, else the Cocoa printer name,
    /// else a synthetic token for a queue-less environment.
    private func boundQueue(of printInfo: NSPrintInfo) -> String {
        PMTicketBridge.currentPrinterID(
            session: PMTicketBridge.session(printInfo),
            fallback: "UnboundQueue")
    }

    func testRoundTripRetainsVendorValue() throws {
        let source = NSPrintInfo()
        XCTAssertTrue(
            PMTicketBridge.setValue(
                "305", forKey: "EPIJ_Qual", locked: false,
                in: PMTicketBridge.settings(source),
                context: "PrintTicketTests"))

        let target = NSPrintInfo()
        let ticket = try PMTicketBridge.serialise(
            source, queue: boundQueue(of: target))
        try PMTicketBridge.restore(ticket, into: target)

        XCTAssertEqual(
            PMTicketBridge.stringValue(
                forKey: "EPIJ_Qual",
                in: PMTicketBridge.settings(target)),
            "305")
    }

    func testPrintSettingsDataIsXmlPlist() throws {
        let ticket = try PMTicketBridge.serialise(
            NSPrintInfo(), queue: "AnyQueue")
        XCTAssertFalse(ticket.printSettings.isEmpty)
        XCTAssertFalse(ticket.pageFormat.isEmpty)
        XCTAssertEqual(
            String(decoding: ticket.printSettings.prefix(5),
                   as: UTF8.self),
            "<?xml")
    }

    func testCrossQueueReplayIsRefused() throws {
        let target = NSPrintInfo()
        let bound = boundQueue(of: target)
        let foreign = "DefinitelyNot_\(bound)"
        try XCTSkipIf(
            bound == foreign,
            "destination resolved to the foreign queue")

        // Sentinel on the destination — a refused restore must leave
        // the target's settings untouched.
        XCTAssertTrue(
            PMTicketBridge.setValue(
                "999", forKey: "EPIJ_Qual", locked: false,
                in: PMTicketBridge.settings(target),
                context: "PrintTicketTests"))

        let source = NSPrintInfo()
        XCTAssertTrue(
            PMTicketBridge.setValue(
                "305", forKey: "EPIJ_Qual", locked: false,
                in: PMTicketBridge.settings(source),
                context: "PrintTicketTests"))
        let ticket = try PMTicketBridge.serialise(
            source, queue: foreign)

        try PMTicketBridge.restore(ticket, into: target)
        XCTAssertEqual(
            PMTicketBridge.stringValue(
                forKey: "EPIJ_Qual",
                in: PMTicketBridge.settings(target)),
            "999")
    }

    func testPrintInfoPlistFallbackRoundTrips() throws {
        let source = NSPrintInfo()
        // The `com.apple.print.PrintSettings` entry only exists once
        // something writes into the attribute dictionary — the
        // ColorSync mirror does this on the real panel path.
        source.dictionary()[
            NSPrintInfo.AttributeKey("com.apple.print.PrintSettings")] =
            ["PMColorMatchingMode": "APCustomColorMatching"]
                as NSDictionary
        let ticket = try PMTicketBridge.serialise(
            source, queue: "AnyQueue")
        let data = try XCTUnwrap(ticket.printInfoPlist)
        let object = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        let dictionary = try XCTUnwrap(object as? [String: Any])
        XCTAssertNotNil(
            dictionary["com.apple.print.PrintSettings"])
    }

    /// 200× serialise loop — a `takeRetainedValue` over/under-release
    /// canary. Byte counts must stay stable; ASan + Malloc Scribble
    /// catches an actual imbalance.
    func testSerialiseIsStableAcrossIterations() throws {
        let source = NSPrintInfo()
        var firstCount: Int?
        for _ in 0..<200 {
            let ticket = try PMTicketBridge.serialise(
                source, queue: "AnyQueue")
            if let first = firstCount {
                XCTAssertEqual(ticket.printSettings.count, first)
            } else {
                firstCount = ticket.printSettings.count
            }
        }
        XCTAssertNotNil(firstCount)
    }
}
