import SwiftUI

/// The result of the last send (or save problem), floating over the reader until it fades.
struct SendToast: View {
    @Bindable var model: ReviewModel

    var body: some View {
        Group {
            if let status = model.status {
                Text(status)
                    .font(.callout)
                    .textSelection(.enabled)  // so the saved review's path can be copied
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect()
                    .padding(12)
                    .task(id: status) {
                        try? await Task.sleep(for: .seconds(8))
                        if model.status == status { model.status = nil }
                    }
                    .accessibilityIdentifier("sendStatus")
                    .transition(.opacity)
            }
        }
        .animation(.default, value: model.status)
    }
}
