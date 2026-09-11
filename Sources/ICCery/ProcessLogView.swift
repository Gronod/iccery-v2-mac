import SwiftUI

/// Shared monospaced process-log disclosure used by Stage 1 and Stage 2.
struct ProcessLogView: View {
    let lines: [String]
    var minHeight: CGFloat = 120
    var maxHeight: CGFloat = 200
    var containerId: String
    var logId: String

    var body: some View {
        DisclosureGroup("Process log") {
            ScrollView {
                Text(lines.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .accessibilityIdentifier(logId)
        }
        .foregroundStyle(Theme.text)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(containerId)
    }
}
