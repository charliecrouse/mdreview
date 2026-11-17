import MDReviewCore
import SwiftUI

struct Sidebar: View {
    var model: ReviewModel

    var body: some View {
        List {
            if model.fileURL != nil {
                Section("Outline") {
                    if model.rendered.headings.isEmpty {
                        Text("No headings").foregroundStyle(.tertiary)
                    }
                    ForEach(model.rendered.headings) { heading in
                        Button {
                            model.reveal(line: heading.line)
                        } label: {
                            Text(heading.title)
                                .fontWeight(heading.level == 1 ? .semibold : .regular)
                                .padding(.leading, CGFloat(heading.level - 1) * 12)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !model.comments.isEmpty {
                    Section("Comments") {
                        ForEach(Array(model.comments.enumerated()), id: \.element.id) { index, comment in
                            Button {
                                model.reveal(comment)
                            } label: {
                                Label {
                                    Text(comment.text.isEmpty ? comment.quote : comment.text).lineLimit(1)
                                } icon: {
                                    Text("\(index + 1)").font(.caption2.bold()).foregroundStyle(.white)
                                        .frame(width: 18, height: 18).background(Circle().fill(.tint))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}
