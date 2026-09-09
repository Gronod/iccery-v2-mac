import AppKit
import ApplicationServices
import ICCeryCore

/// Private Print Manager SPI: `(PMPrintSession, CFStringRef) -> OSStatus`.
/// The second argument is the mode string — never integer `1` (#188).
typealias ColorMatchingModeFunction =
    @convention(c) (PMPrintSession, CFString) -> OSStatus

/// `PMPrintSettingsToOptions` — public symbol, resolved via dlsym so a
/// missing SDK declaration can't break the build.
typealias PrintSettingsToOptionsFunction =
    @convention(c) (PMPrintSettings, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> OSStatus

/// The six-layer unmanaged-printing engine (issue 14, docs/11):
///
/// ① session binding — done by `PrintPanelService` before calling us.
/// ② private SPI `PMSessionSetColorMatchingMode{Lock,,NoLock}` —
///    resolved by `dlsym(RTLD_DEFAULT,…)`; first `(symbol, mode)`
///    returning `0` wins.
/// ③ `PMPrintSettingsSetValue` both `AP_ColorMatchingMode` and
///    `AP.ColorMatchingMode` = `AP_ApplicationColorMatching`, locked.
/// ④ driver "no colour adjustment" pre-select from `lpoptions -l`
///    keys, unlocked (`detectDriverColorBypass`).
/// ⑤ mirror ③+④ into `NSPrintInfo.printSettings` so the PDE sees them.
/// ⑥ after "Use Settings": `PMPrintSettingsToOptions` →
///    `CupsOptionsFilter` → captured `cupsOptions` + `mediaType`.
///
/// All layers degrade gracefully — a missing symbol or non-zero status
/// is logged and the next layer still runs.
@MainActor
struct ColorSyncSuppressor {

    /// Injected for tests: symbol → function. Default resolves via
    /// `dlsym(RTLD_DEFAULT, …)`.
    typealias ModeResolver = (String) -> ColorMatchingModeFunction?
    typealias OptionsResolver = () -> PrintSettingsToOptionsFunction?

    var modeResolver: ModeResolver = Self.dlsymMode
    var optionsResolver: OptionsResolver = Self.dlsymOptions
    var log: (String) -> Void = { AppLogger.shared.log(.info, $0) }

    // MARK: - Layer ② SPI

    /// Walk `ColorMatchingAttempts.attempts` (Lock → plain → NoLock ×
    /// `AP_ApplicationColorMatching` → `ApplicationColorMatching`); the
    /// first call returning `0` wins. `false` when nothing worked.
    @discardableResult
    func applySPIMode(to session: PMPrintSession) -> Bool {
        for attempt in ColorMatchingAttempts.attempts {
            guard let function = modeResolver(attempt.symbol) else {
                continue
            }
            let status = function(session, attempt.mode as CFString)
            if status == 0 {
                log("ColorSync: \(attempt.symbol) accepted "
                    + "\(attempt.mode)")
                return true
            }
        }
        log("ColorSync: no PMSessionSetColorMatchingMode* accepted a "
            + "mode — falling back to PMPrintSettingsSetValue")
        return false
    }

    // MARK: - Layer ③ locked AP_* keys

    /// `PMPrintSettingsSetValue` both key spellings, locked.
    @discardableResult
    func applyLockedKeys(to settings: PMPrintSettings) -> Int {
        var applied = 0
        for key in ColorMatchingAttempts.printSettingsKeys {
            let status = PMPrintSettingsSetValue(
                settings,
                key as CFString,
                ColorMatchingAttempts.applicationMatchingValue as CFString,
                true)
            if status == 0 { applied += 1 }
        }
        if applied == 0 {
            log("ColorSync: PMPrintSettingsSetValue could not lock "
                + "AP_ColorMatchingMode")
        }
        return applied
    }

    // MARK: - Layer ④ driver bypass

    /// Pre-select the driver "no colour adjustment" option, unlocked —
    /// the PDE may override it. Returns the `(key, value)` applied.
    @discardableResult
    func applyDriverBypass(
        to settings: PMPrintSettings,
        optionKeys: Set<String>
    ) -> (key: String, value: String)? {
        guard let bypass = CupsParsers.detectDriverColorBypass(
            optionKeys: optionKeys)
        else { return nil }
        let status = PMPrintSettingsSetValue(
            settings,
            bypass.key as CFString,
            bypass.value as CFString,
            false)
        if status != 0 {
            log("ColorSync: driver bypass \(bypass.key)=\(bypass.value) "
                + "rejected (\(status))")
            return nil
        }
        return bypass
    }

    // MARK: - Layer ⑤ NSPrintInfo mirror

    /// Mirror the applied keys into `printSettings` so the PDE pick
    /// sees them.
    func mirror(
        into printInfo: NSPrintInfo,
        driverBypass: (key: String, value: String)?
    ) {
        let settings = printInfo.printSettings
        for key in ColorMatchingAttempts.printSettingsKeys {
            settings[key as NSString] = ColorMatchingAttempts.applicationMatchingValue as NSString
        }
        if let driverBypass {
            settings[driverBypass.key as NSString] = driverBypass.value as NSString
        }
    }

    // MARK: - Layer ⑥ capture

    /// `PMPrintSettingsToOptions` → filter → `(cupsOptions, mediaType)`.
    /// The malloc'd C string is freed after copying.
    func captureOptions(
        from settings: PMPrintSettings
    ) -> (cupsOptions: String?, mediaType: String?) {
        guard let toOptions = optionsResolver() else {
            log("ColorSync: PMPrintSettingsToOptions unavailable — "
                + "panel options not captured")
            return (nil, nil)
        }
        var raw: UnsafeMutablePointer<CChar>?
        guard toOptions(settings, &raw) == 0, let raw else {
            return (nil, nil)
        }
        defer { free(raw) }
        let unfiltered = String(cString: raw)
        let filtered = CupsOptionsFilter.filter(unfiltered)
        return (
            filtered.isEmpty ? nil : filtered,
            CupsParsers.extractMediaType(fromOptionsString: unfiltered)
        )
    }

    // MARK: - dlsym

    private static func dlsymMode(_ name: String) -> ColorMatchingModeFunction? {
        guard let symbol = dlsym(Self.rtldDefault, name) else { return nil }
        return unsafeBitCast(symbol, to: ColorMatchingModeFunction.self)
    }

    private static func dlsymOptions() -> PrintSettingsToOptionsFunction? {
        guard let symbol = dlsym(Self.rtldDefault, "PMPrintSettingsToOptions")
        else { return nil }
        return unsafeBitCast(symbol, to: PrintSettingsToOptionsFunction.self)
    }

    /// `RTLD_DEFAULT` — `UnsafeMutableRawPointer(bitPattern: -2)`.
    private static var rtldDefault: UnsafeMutableRawPointer? {
        UnsafeMutableRawPointer(bitPattern: -2)
    }
}
