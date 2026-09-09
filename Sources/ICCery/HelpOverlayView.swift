import SwiftUI

/// Reusable help overlay badge that does not reflow layout (#171).
///
/// When `showing` is `true`, a small indicator is rendered as an overlay at the
/// top-trailing corner of the wrapped view. The native `.help` tooltip is always
/// available on hover, so the overlay is purely a visual cue in help mode.
struct HelpOverlay: ViewModifier {
    let text: String
    @Binding var showing: Bool

    func body(content: Content) -> some View {
        content
            .help(text)
            .overlay(alignment: .topTrailing) {
                if showing {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .offset(x: 8, y: -8)
                }
            }
    }
}

extension View {
    /// Adds a non-reflowing help overlay to the view.
    func helpOverlay(_ text: String, showing: Binding<Bool>) -> some View {
        modifier(HelpOverlay(text: text, showing: showing))
    }
}
