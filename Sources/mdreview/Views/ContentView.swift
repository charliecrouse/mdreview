import MDReviewCore
import SwiftUI

struct ContentView: View {
    let model: ReviewModel
    @State private var showInspector = true
    @State private var selectionRect: CGRect?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
                .accessibilityIdentifier("sidebar")
        } detail: {
            Group {
                if model.fileURL == nil {
                    ContentUnavailableView {
                        Label("Open a Markdown file", systemImage: "doc.text")
                    } description: {
                        Text("Drop a .md file here or press ⌘O.")
                    } actions: {
                        Button("Open…") { model.showOpenPanel() }
                    }
                } else {
                    ReaderView(
                        file: model.fileURL,
                        text: model.rendered.text,
                        comments: model.comments,
                        focused: model.focusedComment,
                        scrollTarget: model.scrollTarget,
                        onSelect: { model.selection = $0 },
                        onSelectionRect: { selectionRect = $0 },
                        onComment: { model.addComment() },
                        onOpen: { model.open($0) },
                        onScrolled: { model.scrollTarget = nil }
                    )
                    .overlay(alignment: .topLeading) {
                        if model.canComment, let rect = selectionRect { CommentPill(model: model, selection: rect) }
                    }
                    .overlay(alignment: .bottom) { SendToast(model: model) }
                    .overlay(alignment: .top) {
                        if model.isMissing {
                            Label(
                                "The file was deleted or moved. This is its last version; it reloads if the file "
                                    + "comes back.", systemImage: "exclamationmark.triangle"
                            )
                            .font(.callout)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect()
                            .padding(12)
                            .accessibilityIdentifier("fileMissing")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Dense frost over the window glass keeps body text legible on busy wallpapers;
            // fully opaque under Reduce Transparency or Increase Contrast.
            .background(
                Color(nsColor: .textBackgroundColor)
                    .opacity(reduceTransparency || contrast == .increased ? 1 : 0.86)
            )
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.open(url)
                return true
            }
            .inspector(isPresented: $showInspector) {
                CommentsInspector(model: model)
                    .inspectorColumnWidth(300)
                    .accessibilityIdentifier("inspector")
            }
        }
        .background(BehindWindowGlass().ignoresSafeArea())  // the whole window is glass
        .navigationTitle(model.fileURL?.lastPathComponent ?? "mdreview")
        .navigationSubtitle(
            model.fileURL.map { _ in "\(model.comments.count) comment\(model.comments.count == 1 ? "" : "s")" } ?? ""
        )
        .toolbar {
            ToolbarItem {
                Button {
                    model.send()
                } label: {
                    Label("Send to Agent", systemImage: "paperplane.fill")
                        .labelStyle(.titleAndIcon)
                    // Always laid out, so the button is the same width at 0, 9 and 99 comments.
                    Text("\(model.unresolvedCount)")
                        .font(.caption.bold().monospacedDigit())
                        .frame(minWidth: 22)
                        .background(.white.opacity(0.25), in: .capsule)
                        .opacity(model.unresolvedCount == 0 ? 0 : 1)
                }
                .buttonStyle(.glassProminent)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                        .opacity(model.agentWaiting ? 1 : 0)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
                .disabled(model.unresolvedCount == 0)
                .accessibilityIdentifier("sendToAgent")
                .accessibilityValue("\(model.unresolvedCount) open")
                .help(
                    (model.agentWaiting ? "An agent is waiting. " : "")
                        + "Copy the review, save it and hand it to a waiting mdreview command (⌘↩)"
                )
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button("Comments", systemImage: "sidebar.right") { showInspector.toggle() }
                    .accessibilityIdentifier("toggleInspector")
            }
        }
        .alert(
            "Couldn't open file",
            isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}
