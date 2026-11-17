import MDReviewCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: ReviewModel
    @State private var showInspector = true
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
                        text: model.rendered.text,
                        comments: model.comments,
                        focused: model.focusedComment,
                        scrollTarget: model.scrollTarget,
                        onSelect: { model.selection = $0 },
                        onComment: { model.addComment() },
                        onScrolled: { model.scrollTarget = nil }
                    )
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
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 420)
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
                Button("Add Comment", systemImage: "text.bubble") { model.addComment() }
                    .disabled(!model.canComment)
                    .help("Comment on the selected text (⌥⌘M)")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button {
                    model.send()
                } label: {
                    Label("Send \(model.comments.count) to Agent", systemImage: "paperplane.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.comments.isEmpty)
                .accessibilityIdentifier("sendToAgent")
                .help("Copy the review to the clipboard and save it beside the file (⌘↩)")
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
