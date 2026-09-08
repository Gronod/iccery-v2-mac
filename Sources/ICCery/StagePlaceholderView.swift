import SwiftUI
import ICCeryCore

/// Placeholder stage surface for M1. Real stage UIs arrive in M2–M5
/// (issues #7–#31); Stage 0 lands in M6 (issue #29).
struct StagePlaceholderView: View {
    let stage: WizardStage

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: stage.symbolName)
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text(stage.title)
                .font(.title2)
                .foregroundStyle(Theme.text)
            Text("This stage is not implemented yet — see the milestone plan.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
