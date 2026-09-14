import AppKit
import SwiftUI

/// Detailed license and attribution window (issue #31, docs/21 §Modals).
struct LicenseWindowView: View {
    @Environment(\.dismiss) private var dismiss

    private let icceryLicense: String
    private let argyllLicense: String

    init() {
        // ICCery license from LICENCE.md (embedded at compile time)
        self.icceryLicense = """
# LICENCE

**Copyright (c) 2026 Gordon Bolton**  
**All Rights Reserved.**

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), strictly to view the source code and execute the Software for the sole purpose of personal testing, evaluation, and providing feedback.

Under this licence, you may **not**:

* Modify, alter, or create derivative works of the Software.
* Distribute, publish, or sublicense the Software or any derivatives.
* Use the Software for any commercial or production purpose.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

---

## Bundled ArgyllCMS sidecar binaries

This application bundles and invokes command-line binaries from the Gronod fork of ArgyllCMS. Those binaries are licensed separately under the **GNU Affero General Public License v3 (AGPLv3)**. They are executed strictly as independent subprocesses — they are never linked, loaded, or incorporated into this application — and a copy of `License.txt` is shipped beside the binaries in `Resources/Argyll/`. The terms above apply only to the ICCery application source code, not to the ArgyllCMS binaries.
"""

        // ArgyllCMS license from bundled License.txt
        if let url = Bundle.main.url(forResource: "License", withExtension: "txt", subdirectory: "Argyll"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            self.argyllLicense = content
        } else {
            self.argyllLicense = """
ArgyllCMS license not found — run `scripts/fetch-argyll.sh` to bundle binaries and license.

The ArgyllCMS binaries are licensed under the GNU Affero General Public License v3 (AGPLv3).
A copy of the license should be present at Resources/Argyll/License.txt.

See: https://git.i3omb.com/gronod/argyllcms/releases
"""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Licenses & Attribution")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("closeLicenseBtn")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Theme.panel.opacity(0.9))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Section 1: ICCery License
                    licenseSection(
                        title: "ICCery License",
                        content: icceryLicense,
                        identifier: "icceryLicenseSection"
                    )

                    Divider()

                    // Section 2: ArgyllCMS License
                    licenseSection(
                        title: "ArgyllCMS License (AGPLv3)",
                        content: argyllLicense,
                        identifier: "argyllLicenseSection"
                    )

                    Divider()

                    // Section 3: Attribution & Links
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Attribution & Links")
                            .font(.headline)
                            .foregroundStyle(Theme.text)
                            .accessibilityIdentifier("attributionHeader")

                        VStack(alignment: .leading, spacing: 8) {
                            Link("ArgyllCMS by Graeme Gill → https://www.argyllcms.com/",
                                 destination: URL(string: "https://www.argyllcms.com/")!)
                                .font(.callout)
                                .foregroundStyle(Theme.accent)
                                .accessibilityIdentifier("argyllUpstreamLink")

                            Link("Gronod ArgyllCMS fork (v3.5.0-ICCery.1.x) → https://git.i3omb.com/gronod/argyllcms",
                                 destination: URL(string: "https://git.i3omb.com/gronod/argyllcms")!)
                                .font(.callout)
                                .foregroundStyle(Theme.accent)
                                .accessibilityIdentifier("argyllForkLink")
                        }

                        Text("ICCery bundles and invokes ArgyllCMS binaries as isolated subprocesses per AGPLv3 isolation requirements. The ArgyllCMS binaries are never linked, loaded, or incorporated into the ICCery application binary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("agplIsolationNote")
                    }
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("attributionSection")
                }
                .padding(24)
            }
            .frame(minWidth: 600, minHeight: 500)
            .background(Theme.panel)
        }
        .accessibilityIdentifier("licenseWindow")
    }

    private func licenseSection(title: String, content: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
                .accessibilityIdentifier(identifier + "Header")

            Text(content)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier + "Content")
        }
        .padding(.horizontal, 4)
    }
}