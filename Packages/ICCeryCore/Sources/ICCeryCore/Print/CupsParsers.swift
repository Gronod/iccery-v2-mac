import Foundation

/// One `lpoptions -l` line: `Key/Human Label: *default choice choice`.
public struct CupsOptionListing: Equatable, Sendable {
    /// Machine key before `/`, e.g. `InputSlot` or `CNIJMediaType`.
    public var key: String
    /// Human label after `/`, e.g. `Media Source`.
    public var label: String
    /// All choices, `*` stripped.
    public var choices: [String]
    /// The `*`-prefixed default choice, if any.
    public var defaultChoice: String?

    public init(key: String, label: String, choices: [String], defaultChoice: String?) {
        self.key = key
        self.label = label
        self.choices = choices
        self.defaultChoice = defaultChoice
    }
}

/// Pure parsers for `lpstat` / `lpoptions` / PPD text (issue 12,
/// docs/10–11). Recorded fixtures drive the tests — no live CUPS.
public enum CupsParsers {

    // MARK: - lpstat

    /// `lpstat -e` — one CUPS destination name per line.
    public static func lpstatDestinations(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `lpstat -p` — `printer NAME is idle. enabled since …`,
    /// `printer NAME now printing NAME-1. …`, `printer NAME disabled
    /// since …` → queue → status.
    public static func lpstatStatuses(_ output: String) -> [String: PrinterStatus] {
        var result: [String: PrinterStatus] = [:]
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("printer ") else { continue }
            let rest = text.dropFirst("printer ".count)
            guard let sep = rest.firstIndex(of: " ") else { continue }
            let name = String(rest[..<sep])
            let desc = rest[sep...].lowercased()
            if desc.contains("now printing") {
                result[name] = .printing
            } else if desc.contains("idle") {
                result[name] = .idle
            } else if desc.contains("disabled") || desc.contains("stopped") {
                result[name] = .stopped
            } else {
                result[name] = .unknown
            }
        }
        return result
    }

    /// `lpstat -d` — `system default destination: NAME`, or
    /// `no system default destination` → nil.
    public static func lpstatDefault(_ output: String) -> String? {
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard let colon = text.firstIndex(of: ":") else { continue }
            let name = text[text.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if text.lowercased().hasPrefix("system default destination"),
               !name.isEmpty {
                return name
            }
        }
        return nil
    }

    // MARK: - lpoptions -p <queue>

    /// `lpoptions -p` — `key=value` pairs, values may be
    /// single-quoted (`printer-info='EPSON XP-55 Series'`); bare
    /// flags (`printer-location`) parse as present-with-empty-value.
    public static func lpoptions(_ output: String) -> [(key: String, value: String)] {
        var pairs: [(String, String)] = []
        var index = output.startIndex
        while index < output.endIndex {
            while index < output.endIndex && output[index].isWhitespace {
                index = output.index(after: index)
            }
            guard index < output.endIndex else { break }
            let tokenStart = index
            while index < output.endIndex && output[index] != "=" && !output[index].isWhitespace {
                index = output.index(after: index)
            }
            let key = String(output[tokenStart..<index])
            // A token starting with `=` has no key — skip it (and its
            // value) rather than truncating the whole parse.
            guard !key.isEmpty else {
                if index < output.endIndex && output[index] == "=" {
                    index = output.index(after: index)
                    while index < output.endIndex
                            && !output[index].isWhitespace {
                        index = output.index(after: index)
                    }
                }
                continue
            }
            if index < output.endIndex && output[index] == "=" {
                index = output.index(after: index)
                if index < output.endIndex && output[index] == "'" {
                    // Single-quoted value — scan to closing quote.
                    index = output.index(after: index)
                    let valueStart = index
                    while index < output.endIndex && output[index] != "'" {
                        index = output.index(after: index)
                    }
                    pairs.append((key, String(output[valueStart..<index])))
                    if index < output.endIndex { index = output.index(after: index) }
                } else {
                    let valueStart = index
                    while index < output.endIndex && !output[index].isWhitespace {
                        index = output.index(after: index)
                    }
                    pairs.append((key, String(output[valueStart..<index])))
                }
            } else {
                pairs.append((key, ""))
            }
        }
        return pairs
    }

    /// Display name from `printer-info` in `lpoptions -p` output.
    public static func lpoptionsDisplayName(_ output: String) -> String? {
        guard let value = lpoptions(output)
            .first(where: { $0.key == "printer-info" })?.value,
            !value.isEmpty
        else { return nil }
        return value
    }

    // MARK: - lpoptions -l

    /// `lpoptions -l` — `Key/Human Label: *Default choice2 choice3`.
    /// A missing `/` label reuses the key.
    public static func lpoptionsList(_ output: String) -> [CupsOptionListing] {
        output.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let head = String(line[..<colon])
            let body = line[line.index(after: colon)...]
            let headParts = head.split(separator: "/", maxSplits: 1)
            let key = headParts[0].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            let label = headParts.count > 1
                ? headParts[1].trimmingCharacters(in: .whitespaces)
                : key
            var choices: [String] = []
            var defaultChoice: String?
            for token in body.split(separator: " ") {
                if token.hasPrefix("*") {
                    let value = String(token.dropFirst())
                    defaultChoice = value
                    choices.append(value)
                } else {
                    choices.append(String(token))
                }
            }
            return CupsOptionListing(
                key: key, label: label,
                choices: choices, defaultChoice: defaultChoice)
        }
    }

    // MARK: - PPD enrichment

    /// PPD `*<key> <id>/<Human Label>:` lines → `id → label` map.
    /// Language-qualified forms (`*en_US.<key> id/Label:`) also match.
    /// Precedence is deterministic, not positional (#181): unqualified
    /// `*Key` > `en_US.` > `en.` > first-qualified-seen, so a trailing
    /// locale block (Canon `th.CNIJMediaType`) can never overwrite the
    /// base English labels — and a qualified-only id still gets its
    /// first-seen qualified label (R9).
    public static func ppdChoiceLabels(_ ppd: String, key: String) -> [String: String] {
        var hits: [String: [(qualifier: String?, label: String)]] = [:]
        for rawLine in ppd.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("*"), !line.hasPrefix("**") else { continue }
            line = String(line.dropFirst())
            // Optional locale qualifier: `en_US.InputSlot` → `InputSlot`.
            // Only strip when the part before the first `.` looks like
            // a locale (short `xx`/`xx_YY`); real keys containing dots
            // are left alone. The qualifier is recorded for precedence
            // rather than dropped (#181).
            var qualifier: String?
            if let dot = line.firstIndex(of: ".") {
                let prefix = line[..<dot]
                let looksLikeLocale = (2...5).contains(prefix.count)
                    && prefix.allSatisfy { $0.isLetter || $0 == "_" }
                    && (prefix.count == 2 || prefix.contains("_"))
                let candidate = line[line.index(after: dot)...]
                if looksLikeLocale && candidate.hasPrefix(key) {
                    qualifier = prefix.lowercased()
                    line = String(candidate)
                }
            }
            guard line.hasPrefix(key) else { continue }
            var rest = line[line.index(line.startIndex, offsetBy: key.count)...]
                .trimmingCharacters(in: .whitespaces)
            guard let colon = rest.firstIndex(of: ":") else { continue }
            rest = String(rest[..<colon])
            // `<id>/<Human label>` — human label after the last `/`.
            guard let slash = rest.firstIndex(of: "/") else { continue }
            let id = ppdUnescape(String(rest[..<slash])
                .trimmingCharacters(in: .whitespaces))
            let human = ppdUnescape(String(rest[rest.index(after: slash)...])
                .trimmingCharacters(in: .whitespaces))
            guard !id.isEmpty else { continue }
            hits[id, default: []].append(
                (qualifier, human.isEmpty ? id : human))
        }
        var map: [String: String] = [:]
        for (id, candidates) in hits {
            // First occurrence wins inside each qualifier class, in
            // file order — same as the old sequential behaviour.
            map[id] = candidates.first { $0.qualifier == nil }?.label
                ?? candidates.first { $0.qualifier == "en_us" }?.label
                ?? candidates.first { $0.qualifier == "en" }?.label
                ?? candidates[0].label
        }
        return map
    }

    /// PPD `<XX>` hex escapes → the literal byte (`<2F>` → `/`,
    /// `<20>` → space). Anything that is not `<` + two hex digits +
    /// `>` passes through untouched (#181).
    private static func ppdUnescape(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "<",
                  let hexEnd = text.index(
                      index, offsetBy: 3, limitedBy: text.endIndex),
                  hexEnd < text.endIndex, text[hexEnd] == ">",
                  let byte = UInt8(
                      text[text.index(after: index)..<hexEnd], radix: 16)
            else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }
            result.append(Character(UnicodeScalar(byte)))
            index = text.index(after: hexEnd)
        }
        return result
    }

    // MARK: - Detection (docs/11)

    /// Media-type option key in preference order — used both to read a
    /// captured value and to emit `-o <key>=<media>`.
    public static let mediaTypeKeys = [
        "CNIJMediaType", "EPIJ_Medi", "StpMediaType", "MediaType"
    ]

    public static func detectMediaTypeKey(optionKeys: Set<String>) -> String? {
        mediaTypeKeys.first { optionKeys.contains($0) }
    }

    /// Media type from a captured `key=value key=value` options string.
    /// Prefers `MediaType` (docs/11 §tests), then the remaining roster
    /// keys in detection order — `CNIJMediaType`, `EPIJ_Medi`,
    /// `StpMediaType` (#186 capture-return).
    public static func extractMediaType(fromOptionsString options: String) -> String? {
        let pairs = lpoptions(options)
        if let v = pairs.first(where: { $0.key == "MediaType" })?.value {
            return v
        }
        for key in mediaTypeKeys where key != "MediaType" {
            if let v = pairs.first(where: { $0.key == key })?.value {
                return v
            }
        }
        return nil
    }

    /// Print-quality option key in preference order — vendor-first,
    /// weakest last (#183). `OutputMode`/`Resolution` sit last: on some
    /// drivers they are colour-mode keys, not quality (#180).
    /// `CNIJPrintMode2`/`CNIJPQualitySlider` are deferred (#16).
    public static let qualityKeys = [
        "EPIJ_Qual", "CNIJPrintQuality", "CNIJQuality",
        "cupsPrintQuality", "PrintQuality", "Quality", "StpQuality",
        "EPIJ_Quality", "OutputMode", "Resolution",
    ]

    public static func detectQualityKey(optionKeys: Set<String>) -> String? {
        qualityKeys.first { optionKeys.contains($0) }
    }

    /// A single value from a captured `key=value key=value` options
    /// string — case-insensitive key match (#183 capture-return).
    public static func extractOption(
        named key: String,
        fromOptionsString options: String
    ) -> String? {
        lpoptions(options).first {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }?.value
    }

    /// Print-quality token from a captured options string — the queue's
    /// quality key is detected from the roster before extracting (#183).
    public static func extractQuality(fromOptionsString options: String) -> String? {
        let pairs = lpoptions(options)
        guard let key = detectQualityKey(
            optionKeys: Set(pairs.map(\.key)))
        else { return nil }
        return pairs.first(where: { $0.key == key })?.value
    }

    /// `orientation-requested=3|4` → `"portrait"`/`"landscape"` (#183).
    public static func extractOrientation(fromOptionsString options: String) -> String? {
        extractOption(named: "orientation-requested", fromOptionsString: options)
            .map { $0 == "4" ? "landscape" : "portrait" }
    }

    /// Driver "no colour adjustment" key=value for `lpoptions -l` keys
    /// (docs/11 layer ④): Canon `CNIJIntent2=4` else `CNIJIntent=4`;
    /// Epson `EPIJ_CCor=0` when the key exists else `EPIJ_CMat=3`;
    /// Gutenprint `StpColorCorrection=Uncorrected`; generic
    /// `ColorCorrection=Uncorrected`; `EpsonColorMode=Off`.
    public static func detectDriverColorBypass(
        optionKeys: Set<String>
    ) -> (key: String, value: String)? {
        if optionKeys.contains("CNIJIntent2") { return ("CNIJIntent2", "4") }
        if optionKeys.contains("CNIJIntent") { return ("CNIJIntent", "4") }
        if optionKeys.contains("EPIJ_CCor") { return ("EPIJ_CCor", "0") }
        if optionKeys.contains("EPIJ_CMat") { return ("EPIJ_CMat", "3") }
        if optionKeys.contains("StpColorCorrection") {
            return ("StpColorCorrection", "Uncorrected")
        }
        if optionKeys.contains("ColorCorrection") {
            return ("ColorCorrection", "Uncorrected")
        }
        if optionKeys.contains("EpsonColorMode") { return ("EpsonColorMode", "Off") }
        return nil
    }

    /// The key=value pairs of colour-bypass keys — used to detect
    /// whether captured options already carry a bypass.
    public static let bypassKeys: Set<String> = [
        "CNIJIntent2", "CNIJIntent", "EPIJ_CMat", "EPIJ_CCor",
        "EPIJ_OSColMat", "ColorCorrection", "StpColorCorrection",
        "EpsonColorMode",
    ]
}
