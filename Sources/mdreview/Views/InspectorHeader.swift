import SwiftUI

struct InspectorHeader: View {
    @Bindable var model: ReviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("An agent is waiting", systemImage: "circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .opacity(model.agentWaiting ? 1 : 0)
                .accessibilityHidden(!model.agentWaiting)
                .accessibilityIdentifier("agentWaiting")
            HStack(spacing: 4) {
                Text("Comments").font(.headline)
                Spacer()
                if let position = model.focusedPosition {
                    Text("\(position) of \(model.comments.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button("Previous Comment", systemImage: "chevron.up") { model.step(by: -1) }
                Button("Next Comment", systemImage: "chevron.down") { model.step(by: 1) }
                Button("Add Comment", systemImage: "plus") { model.addComment() }
                    .disabled(!model.canComment)
                    .help("Comment on the selected text (⌥⌘M)")
                    .accessibilityIdentifier("addComment")
                Button("Add Page Comment", systemImage: "doc.text") { model.addPageComment() }
                    .help("Comment on the whole file (⇧⌥⌘M)")
                    .accessibilityIdentifier("addPageComment")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(model.fileURL == nil)
            Picker("Show", selection: $model.filter) {
                ForEach(CommentFilter.allCases) { filter in
                    Text("\(filter.rawValue) \(count(filter))").tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 0))
    }

    private func count(_ filter: CommentFilter) -> Int {
        model.comments.count(where: filter.includes)
    }
}
