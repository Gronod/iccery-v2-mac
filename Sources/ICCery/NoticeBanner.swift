import SwiftUI

/// Banner notice model — the v2 equivalent of `#wizardNotification`
/// (docs/21 §Banner).
struct Notice: Identifiable, Equatable {
    enum Kind: Equatable {
        case info, warning, error

        var symbolName: String {
            switch self {
            case .info:    return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error:   return "xmark.octagon"
            }
        }

        var tint: Color {
            switch self {
            case .info:    return Theme.accent
            case .warning: return .orange
            case .error:   return .red
            }
        }

        var accessibilityValue: String {
            switch self {
            case .info:    return "info"
            case .warning: return "warning"
            case .error:   return "error"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let text: String
    /// Auto-dismiss interval; `nil` keeps the banner until closed.
    var autoHideAfter: TimeInterval? = 6
}

struct NoticeBanner: View {
    let notice: Notice
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notice.kind.symbolName)
                .foregroundStyle(notice.kind.tint)
            Text(notice.text)
                .font(.callout)
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .accessibilityIdentifier("noticeText")
                .accessibilityValue(notice.text)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Theme.border),
            alignment: .bottom
        )
    }
}
