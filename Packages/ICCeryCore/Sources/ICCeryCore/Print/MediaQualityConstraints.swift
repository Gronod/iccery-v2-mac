import Foundation

/// Per-media quality validity (#214): which of the queue's quality
/// tokens the driver actually accepts for a given media type. The
/// answer is not in `lpoptions -l`, IPP, or standard PPD
/// `*UIConstraints` for the two driver families handled here —
///
///  - Epson InkjetPrinter2: `*EPIJUIConstraint: <cond>|<forbidden>`
///    lines in the machine bundle's
///    `…/Contents/Resources/PDEData.dat`. A rule forbids its RHS
///    choice while every LHS `*<key> <value>` term holds. LHS keys
///    other than the media key (`EPIJ_PSrc`, `EPIJ_FdSo`,
///    `EPIJ_Ink_`, …) are evaluated against the queue's `lpoptions`
///    defaults — reproducing the driver's PDE state when it opens.
///  - Canon BJPrinter: `*CNIJNameTblPath` + `*CNIJTableID` PPD keys
///    locate `cnb_<TableID>0.tbl`, a binary record DB whose 20-byte
///    `{u16 0x30, u16 1, u32 0, u16 family, u16 flag, u32 mediaID,
///    u16 0, u16 quality}` records enumerate the allowed
///    `CNIJPrintQuality` values per `CNIJMediaType` (`mediaID`
///    `| 0x10000` marks the borderless variant of the same media).
///  - Generic: standard PPD `*UIConstraints:`/`*Constraints:` pairs
///    (Gutenprint etc.) — first non-empty source wins.
///
/// Every parser is pure; file access is injected so tests need no
/// installed driver. Failure or absence yields an empty map — callers
/// treat that as "unconstrained" and keep the full quality list.
public enum MediaQualityConstraints {

    /// media-type id → allowed quality ids. Sources tried in order
    /// (PPD constraints → Epson `PDEData.dat` → Canon `cnb` table);
    /// the first source producing any entries wins.
    public static func resolve(
        listings: [CupsOptionListing],
        ppd: String?,
        readFile: (URL) -> Data? = { try? Data(contentsOf: $0) }
    ) -> [String: Set<String>] {
        let optionKeys = Set(listings.map(\.key))
        guard let mediaKey = CupsParsers.detectMediaTypeKey(
                optionKeys: optionKeys),
              let qualityKey = CupsParsers.detectQualityKey(
                optionKeys: optionKeys),
              let mediaListing = listings.first(where: {
                  $0.key == mediaKey }),
              let qualityListing = listings.first(where: {
                  $0.key == qualityKey })
        else { return [:] }
        let mediaIDs = Set(mediaListing.choices)
        let qualityIDs = Set(qualityListing.choices)
        let defaults = Dictionary(
            listings.compactMap { l in l.defaultChoice.map { (l.key, $0) } },
            uniquingKeysWith: { first, _ in first })
        guard let ppd else { return [:] }

        let ppdMap = allowedMap(
            forbidden: ppdUIConstraints(
                ppd, mediaKey: mediaKey, qualityKey: qualityKey,
                mediaIDs: mediaIDs, qualityIDs: qualityIDs),
            mediaIDs: mediaIDs, qualityIDs: qualityIDs)
        if !ppdMap.isEmpty { return ppdMap }

        if let url = epijPDEDataPath(ppd: ppd),
           let data = readFile(url),
           let dat = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) {
            let map = allowedMap(
                forbidden: epijUIConstraints(
                    dat, mediaKey: mediaKey, qualityKey: qualityKey,
                    mediaIDs: mediaIDs, qualityIDs: qualityIDs,
                    defaults: defaults),
                mediaIDs: mediaIDs, qualityIDs: qualityIDs)
            if !map.isEmpty { return map }
        }

        if let url = cnijTablePath(ppd: ppd),
           let data = readFile(url) {
            let map = cnijMediaQualityTable(
                data, mediaIDs: mediaIDs, qualityIDs: qualityIDs)
            if !map.isEmpty { return map }
        }
        return [:]
    }

    // MARK: - PPD keyword lookup

    /// `*<key>: <value>` or `*<key>: "<value>"` → the value.
    /// Exact key match — `*CNIJTableIDFoo:` must not satisfy a lookup
    /// for `CNIJTableID`.
    public static func ppdKeyword(_ ppd: String, _ key: String) -> String? {
        for raw in ppd.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*\(key)") else { continue }
            let rest = line.dropFirst(key.count + 1)
            guard rest.first == ":" else { continue }
            var value = rest.dropFirst()
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { return value }
        }
        return nil
    }

    // MARK: - Generic PPD constraints

    /// `*UIConstraints:`/`*Constraints:` lines pair two conflicting
    /// option choices; the ones naming both the media key and the
    /// quality key produce forbidden (media, quality) pairs.
    /// `*cupsUIConstraints` resolver triples do not match the
    /// `*…Constraints:` prefixes, so they are skipped naturally.
    public static func ppdUIConstraints(
        _ ppd: String,
        mediaKey: String,
        qualityKey: String,
        mediaIDs: Set<String>,
        qualityIDs: Set<String>
    ) -> [String: Set<String>] {
        var forbidden: [String: Set<String>] = [:]
        for raw in ppd.split(separator: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("*UIConstraints:") {
                line = String(line.dropFirst("*UIConstraints:".count))
            } else if line.hasPrefix("*Constraints:") {
                line = String(line.dropFirst("*Constraints:".count))
            } else {
                continue
            }
            let terms = constraintTerms(line)
            guard let media = terms[mediaKey], mediaIDs.contains(media),
                  let quality = terms[qualityKey],
                  qualityIDs.contains(quality)
            else { continue }
            forbidden[media, default: []].insert(quality)
        }
        return forbidden
    }

    // MARK: - Epson PDEData.dat

    /// `EPIJDriverBasePath` + `EPIJMachineBundleName` → the machine
    /// bundle's `Contents/Resources/PDEData.dat` (uniform across the
    /// InkjetPrinter2 family).
    public static func epijPDEDataPath(ppd: String) -> URL? {
        guard let base = ppdKeyword(ppd, "EPIJDriverBasePath"),
              let bundle = ppdKeyword(ppd, "EPIJMachineBundleName")
        else { return nil }
        return URL(fileURLWithPath: base)
            .appendingPathComponent("Machine")
            .appendingPathComponent(bundle)
            .appendingPathComponent("Contents/Resources/PDEData.dat")
    }

    /// `*EPIJUIConstraint:` forbidden-pair rules → (media, quality)
    /// pairs the driver greys out. A rule *fires* when its LHS
    /// `*<mediaKey>` term equals the media (absent media term →
    /// applies to every media) and every other LHS term's value
    /// equals that key's `lpoptions` default. A term whose key the
    /// queue does not advertise counts as satisfied — hiding a usable
    /// quality is a soft restriction, while showing an invalid one
    /// re-creates the reported print failure.
    public static func epijUIConstraints(
        _ dat: String,
        mediaKey: String,
        qualityKey: String,
        mediaIDs: Set<String>,
        qualityIDs: Set<String>,
        defaults: [String: String]
    ) -> [String: Set<String>] {
        var forbidden: [String: Set<String>] = [:]
        for raw in dat.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*EPIJUIConstraint:"),
                  let bar = line.firstIndex(of: "|")
            else { continue }
            let rhs = constraintTerms(
                String(line[line.index(after: bar)...]))
            guard let quality = rhs[qualityKey],
                  qualityIDs.contains(quality)
            else { continue }
            let lhs = constraintTerms(
                String(line[
                    line.index(
                        line.startIndex,
                        offsetBy: "*EPIJUIConstraint:".count)..<bar]))
            // Non-media terms must hold at the queue's defaults;
            // a key absent from `defaults` is satisfied (see above).
            let fires = lhs.allSatisfy { key, value in
                key == mediaKey || value.isEmpty
                    || (defaults[key].map { $0 == value } ?? true)
            }
            guard fires else { continue }
            if let media = lhs[mediaKey] {
                guard mediaIDs.contains(media) else { continue }
                forbidden[media, default: []].insert(quality)
            } else {
                for media in mediaIDs {
                    forbidden[media, default: []].insert(quality)
                }
            }
        }
        return forbidden
    }

    // MARK: - Canon cnb table

    /// `CNIJNameTblPath` + `CNIJTableID` → `cnb_<TableID>0.tbl`.
    public static func cnijTablePath(ppd: String) -> URL? {
        guard let dir = ppdKeyword(ppd, "CNIJNameTblPath"),
              let tableID = ppdKeyword(ppd, "CNIJTableID")
        else { return nil }
        return URL(fileURLWithPath: dir)
            .appendingPathComponent("cnb_\(tableID)0.tbl")
    }

    /// Scans the Canon table for 20-byte LE records anchored on
    /// `30 00 01 00 00 00 00 00`: `{u16 family, u16 flag,
    /// u32 mediaID, u16 pad, u16 quality}` follows the anchor.
    /// A row counts only when `pad == 0`, `mediaID & 0xFFFF` is a
    /// listed media id, and `quality` is a listed quality id — so
    /// unrelated tables cannot inject false entries. Records carry a
    /// `family` field (0x03 on the Pro9500 II); the modal family is
    /// used so sibling record layouts in the same file are ignored.
    /// Returns allowed (not forbidden) sets directly.
    public static func cnijMediaQualityTable(
        _ data: Data,
        mediaIDs: Set<String>,
        qualityIDs: Set<String>
    ) -> [String: Set<String>] {
        let mediaNums = Set(mediaIDs.compactMap { UInt32($0) })
        let qualityNums = Set(qualityIDs.compactMap { UInt16($0) })
        guard !mediaNums.isEmpty, !qualityNums.isEmpty else {
            return [:]
        }
        let anchor: [UInt8] = [0x30, 0x00, 0x01, 0x00,
                               0x00, 0x00, 0x00, 0x00]
        var rows: [UInt16: [(media: UInt32, quality: UInt16)]] = [:]
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var i = 0
            while i + 20 <= buffer.count {
                if memcmp(base + i, anchor, anchor.count) == 0 {
                    let family = readU16(base, i + 8)
                    let media = readU32(base, i + 12)
                    let pad = readU16(base, i + 16)
                    let quality = readU16(base, i + 18)
                    let baseMedia = media & 0xFFFF
                    if pad == 0,
                       mediaNums.contains(baseMedia),
                       qualityNums.contains(quality) {
                        rows[family, default: []].append(
                            (baseMedia, quality))
                    }
                }
                i += 2
            }
        }
        guard let dominant = rows.max(by: { $0.value.count < $1.value.count })
        else { return [:] }
        var map: [String: Set<String>] = [:]
        for row in dominant.value {
            map[String(row.media), default: []].insert(String(row.quality))
        }
        // Keep strict subsets only — a media with the full set (or an
        // empty one) is unconstrained as far as the UI is concerned.
        map = map.filter { _, ids in
            !ids.isEmpty && ids != qualityIDs
        }
        return map
    }

    // MARK: - Shared

    /// `*<key> <value>` term extraction for both PPD and Epson
    /// constraint syntax. A `*<key>` not followed by a value is a
    /// wildcard term (empty-string value → always satisfied).
    private static func constraintTerms(_ text: String) -> [String: String] {
        var terms: [String: String] = [:]
        let tokens = text.split(separator: " ").map(String.init)
        var index = 0
        while index < tokens.count {
            guard tokens[index].hasPrefix("*") else {
                index += 1
                continue
            }
            let key = String(tokens[index].dropFirst())
            if index + 1 < tokens.count,
               !tokens[index + 1].hasPrefix("*") {
                terms[key] = tokens[index + 1]
                index += 2
            } else {
                terms[key] = ""
                index += 1
            }
        }
        return terms
    }

    /// forbidden (media → quality ids) → allowed map entries,
    /// emitting only strict non-empty subsets: a media whose allowed
    /// set is empty or equals the full roster is unconstrained as far
    /// as the picker is concerned.
    private static func allowedMap(
        forbidden: [String: Set<String>],
        mediaIDs: Set<String>,
        qualityIDs: Set<String>
    ) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for media in mediaIDs {
            let allowed = qualityIDs.subtracting(forbidden[media] ?? [])
            if !allowed.isEmpty, allowed != qualityIDs {
                map[media] = allowed
            }
        }
        return map
    }

    private static func readU16(_ base: UnsafeRawPointer, _ offset: Int) -> UInt16 {
        UInt16(base.load(fromByteOffset: offset, as: UInt8.self))
            | UInt16(base.load(fromByteOffset: offset + 1, as: UInt8.self)) << 8
    }

    private static func readU32(_ base: UnsafeRawPointer, _ offset: Int) -> UInt32 {
        UInt32(base.load(fromByteOffset: offset, as: UInt8.self))
            | UInt32(base.load(fromByteOffset: offset + 1, as: UInt8.self)) << 8
            | UInt32(base.load(fromByteOffset: offset + 2, as: UInt8.self)) << 16
            | UInt32(base.load(fromByteOffset: offset + 3, as: UInt8.self)) << 24
    }
}
