import SwiftUI
import ICCeryCore

/// Settings sheet (issue #5, docs/21 §Settings). Dark-theme Form with
/// the full v1 field set; ΔE validation shows inline under the fields.
struct SettingsView: View {
    @StateObject var model = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    private static let instruments: [(code: String, label: String)] = [
        ("i1", "X-Rite i1Pro / i1Pro 2"),
        ("p3", "X-Rite i1Pro 3 / 3 Plus"),
        ("CM", "ColorMunki"),
        ("SS", "Specbos / Spectraval"),
        ("20", "Gretag i1Display 2"),
        ("22", "X-Rite i1Display Pro / ColorMunki Display"),
        ("41", "Datacolor Spyder 4/5"),
        ("51", "Spyder X"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Argyll") {
                    HStack {
                        TextField(
                            "Bundled sidecars",
                            text: Binding(
                                get: { model.settings.argyllBinaryDir ?? "" },
                                set: {
                                    model.settings.argyllBinaryDir =
                                        $0.isEmpty ? nil : $0
                                }
                            )
                        )
                        Button("Browse…") {
                            if let dir = FileDialogService.shared.selectDirectory() {
                                model.settings.argyllBinaryDir = dir.path
                            }
                        }
                    }
                    Text("Leave empty to use the bundled Argyll tools.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker(
                        "Default instrument",
                        selection: Binding(
                            get: { model.settings.defaultInstrument ?? "" },
                            set: {
                                model.settings.defaultInstrument =
                                    $0.isEmpty ? nil : $0
                            }
                        )
                    ) {
                        Text("None").tag("")
                        ForEach(Self.instruments, id: \.code) {
                            Text($0.label).tag($0.code)
                        }
                    }
                    Text("Seeds Spot Read and Stage 3 when the instrument is plugged in. printtarg -i is still chosen on Stage 2.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Enable i1Pro 2 LEDs",
                        isOn: $model.settings.enableI1Pro2Leds
                    )
                }

                Section("Verification") {
                    TextField(
                        "Good ΔE ≤",
                        value: $model.settings.deltaEGoodMax,
                        format: .number
                    )
                    .accessibilityIdentifier("settingsDeltaEGood")

                    TextField(
                        "Warning ΔE ≤",
                        value: $model.settings.deltaEWarningMax,
                        format: .number
                    )
                    .accessibilityIdentifier("settingsDeltaEWarning")

                    Text("Swatch and verify status use these as the green / amber cutoffs. Fail is anything above Warning.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(model.validationErrors, id: \.self) { error in
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Calibration") {
                    TextField(
                        "Stale after (days)",
                        value: $model.settings.calibrationStaleDays,
                        format: .number
                    )
                    .accessibilityIdentifier("settingsCalStaleDays")
                }

                Section("Profile install") {
                    Picker(
                        "Install location",
                        selection: $model.settings.defaultInstallLocation
                    ) {
                        Text("User library").tag(InstallLocation.user)
                        Text("System library").tag(InstallLocation.system)
                    }
                    Toggle(
                        "Ask before overwriting a profile",
                        isOn: $model.settings.askBeforeOverwriteProfile
                    )
                    Toggle(
                        "Open ColorSync after install",
                        isOn: $model.settings.openColorPanelAfterInstall
                    )
                }

                Section("Logging") {
                    Picker(
                        "Log level",
                        selection: Binding(
                            get: { model.settings.logLevel },
                            set: { model.settings.logLevel = $0 }
                        )
                    ) {
                        Text("Default").tag(LogLevel?.none)
                        ForEach(LogLevel.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag(LogLevel?.some($0))
                        }
                    }
                    HStack {
                        Button("Open log folder") { model.openLogFolder() }
                        Button("Copy path") { model.copyLogPath() }
                        Button("Copy excerpt") { model.copyLogExcerpt() }
                    }
                }
            }
            .padding(.leading, 45)

            Divider()

            HStack {
                if model.savedFlash {
                    Text("Saved")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if model.save() { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
        .background(Theme.background)
    }
}
