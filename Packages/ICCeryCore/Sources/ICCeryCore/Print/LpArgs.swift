import Foundation

/// Errors from `buildLpArgs`.
public enum LpArgsError: LocalizedError, Equatable {
    case unsanitisedOption(String)

    public var errorDescription: String? {
        switch self {
        case .unsanitisedOption(let option):
            return "Captured CUPS option contains unsafe characters: \(option)"
        }
    }
}

/// `lp` argv builder — issue 15, docs/11 `build_lp_args`.
///
/// ```
/// lp -d <queue> -t "ICCery Target - <file>"
///    -o AP_ColorMatchingMode=AP_ApplicationColorMatching
///    -o AP.ColorMatchingMode=AP_ApplicationColorMatching
///    <captured cups_options>
///    <media_type, if no media key already captured>
///    <quality, if no quality key already captured> (#183)
///    <driver bypass, if no bypass key captured>
///    <orientation-requested=3|4, unless captured>
///    <PageSize, unless captured>
///    <tiff>
/// ```
///
/// - **Never `-o raw`** — `raw` skips the raster filter that honours
///   `AP_ApplicationColorMatching` (#92).
/// - Captured options **win** over explicit fields: any key already
///   present (case-insensitive) suppresses the derived `-o`.
/// - Captured keys/values are sanitised — `;`, newlines, or shell
///   metacharacters throw `unsanitisedOption`; args are passed as a
///   `Process` argv array, never through a shell.
/// - The TIFF path is always the **last** argument.
public enum LpArgs {

    /// `options` = the captured `PrintOptions`; `optionKeys` = the
    /// queue's `lpoptions -l` key set (for media-key/bypass detection).
    public static func build(
        queue: String,
        tiffPath: String,
        options: PrintOptions,
        optionKeys: Set<String>
    ) throws -> [String] {
        var argv: [String] = [
            "-d", queue,
            "-t", "ICCery Target - \((tiffPath as NSString).lastPathComponent)",
            "-o", "AP_ColorMatchingMode=AP_ApplicationColorMatching",
            "-o", "AP.ColorMatchingMode=AP_ApplicationColorMatching",
        ]
        var addedKeys: Set<String> = [
            "ap_colormatchingmode", "ap.colormatchingmode",
        ]

        // Captured CUPS options — sanitised, lowercased-key dedup.
        if let captured = options.cupsOptions, !captured.isEmpty {
            // Newlines can't survive the tokeniser — check the raw
            // string so embedded line breaks are still rejected.
            if captured.contains("\n") || captured.contains("\r") {
                throw LpArgsError.unsanitisedOption(captured)
            }
            for pair in CupsParsers.lpoptions(captured) {
                try sanitize(pair.key, pair.value)
                let lowered = pair.key.lowercased()
                // Defence in depth: never let a captured `raw` reach
                // argv — `-o raw` skips the raster filter that honours
                // AP_ApplicationColorMatching (#92).
                if lowered == "raw" { continue }
                guard !addedKeys.contains(lowered) else { continue }
                addedKeys.insert(lowered)
                argv += ["-o", "\(pair.key)=\(pair.value)"]
            }
        }

        // Media type — only when the captured options didn't carry one.
        if let mediaType = options.mediaType,
           let mediaKey = CupsParsers.detectMediaTypeKey(optionKeys: optionKeys),
           !addedKeys.contains(mediaKey.lowercased()) {
            addedKeys.insert(mediaKey.lowercased())
            argv += ["-o", "\(mediaKey)=\(mediaType)"]
        }

        // Print quality — after media, before the driver bypass; the
        // detected queue key is skipped when already captured (#183).
        if let quality = options.quality,
           let qualityKey = CupsParsers.detectQualityKey(optionKeys: optionKeys),
           !addedKeys.contains(qualityKey.lowercased()) {
            addedKeys.insert(qualityKey.lowercased())
            argv += ["-o", "\(qualityKey)=\(quality)"]
        }

        // Driver colour bypass — when no bypass key was captured. NOT
        // gated on ppdUncorrectedPassthrough (macOS always bypasses).
        let capturedKeys = Set(
            CupsParsers.lpoptions(options.cupsOptions ?? "")
                .map { $0.key })
        if capturedKeys.isDisjoint(with: CupsParsers.bypassKeys),
           let bypass = CupsParsers.detectDriverColorBypass(optionKeys: optionKeys),
           !addedKeys.contains(bypass.key.lowercased()) {
            addedKeys.insert(bypass.key.lowercased())
            argv += ["-o", "\(bypass.key)=\(bypass.value)"]
        }

        // Orientation — portrait=3, landscape=4.
        if let orientation = options.orientation,
           !addedKeys.contains("orientation-requested") {
            let value = orientation == "landscape" ? "4" : "3"
            addedKeys.insert("orientation-requested")
            argv += ["-o", "orientation-requested=\(value)"]
        }

        // PageSize — the printtarg layout page size.
        if let paperSize = options.paperSize, !paperSize.isEmpty,
           !addedKeys.contains("pagesize") {
            argv += ["-o", "PageSize=\(paperSize)"]
        }

        argv.append(tiffPath)
        return argv
    }

    /// Reject shell/metachar injection — args go to `Process` as an
    /// argv array, but a hostile captured string must not smuggle a
    /// second option or command.
    static func sanitize(_ key: String, _ value: String) throws {
        let forbidden = CharacterSet(charactersIn: ";\n\r`|$&<>\\\"'")
        if key.rangeOfCharacter(from: forbidden) != nil
            || value.rangeOfCharacter(from: forbidden) != nil
            || key.isEmpty {
            throw LpArgsError.unsanitisedOption("\(key)=\(value)")
        }
    }
}
