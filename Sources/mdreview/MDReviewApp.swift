import AppKit
import MDReviewCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct MDReviewApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    private var model: ReviewModel { delegate.model }

    init() {
        // Don't let AppKit turn `mdreview file.md` into an open-documents launch, which
        // suppresses the initial window; the delegate opens the path itself.
        UserDefaults.standard.register(defaults: ["NSTreatUnknownArgumentsAsOpen": "NO"])
    }

    var body: some Scene {
        Window("mdreview", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Review") {
                Button("Add Comment") { model.addComment() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    .disabled(!model.canComment)
                Button("Send to Agent") { model.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.comments.isEmpty)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ReviewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // `swift run mdreview path/to/file.md`
        if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            model.open(URL(fileURLWithPath: path))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Model

@MainActor @Observable
final class ReviewModel {
    var fileURL: URL?
    var rendered = RenderedMarkdown()
    var comments: [ReviewComment] = []
    var selection = NSRange(location: 0, length: 0)
    var focusedComment: ReviewComment.ID?
    var scrollTarget: NSRange?
    var status: String?
    var error: String?

    var canComment: Bool { MarkdownRenderer.lineRange(of: selection, in: rendered.text) != nil }

    func open(_ url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            rendered = MarkdownRenderer.render(source)
            comments = []
            selection = NSRange(location: 0, length: 0)
            focusedComment = nil
            status = nil
        } catch {
            self.error = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func addComment() {
        guard let lines = MarkdownRenderer.lineRange(of: selection, in: rendered.text) else { return }
        let quote = rendered.text.attributedSubstring(from: selection).string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let comment = ReviewComment(lines: lines, quote: quote, range: selection)
        comments.append(comment)
        comments.sort { ($0.lines.lowerBound, $0.range.location) < ($1.lines.lowerBound, $1.range.location) }
        focusedComment = comment.id
    }

    func delete(_ id: ReviewComment.ID) {
        comments.removeAll { $0.id == id }
        if focusedComment == id { focusedComment = nil }
    }

    func reveal(_ comment: ReviewComment) {
        focusedComment = comment.id
        scrollTarget = comment.range
    }

    func reveal(line: Int) {
        if let range = MarkdownRenderer.range(ofLine: line, in: rendered.text) {
            scrollTarget = NSRange(location: range.location, length: 0)
        }
    }

    /// v1 "send": copy the batched review to the clipboard and save it beside the file.
    func send() {
        guard let url = fileURL, !comments.isEmpty else { return }
        let review = ReviewExport.markdown(file: url, comments: comments)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review, forType: .string)
        let out = ReviewExport.reviewURL(for: url)
        do {
            try review.write(to: out, atomically: true, encoding: .utf8)
            status = "Copied \(comments.count) comment\(comments.count == 1 ? "" : "s") · saved \(out.lastPathComponent)"
        } catch {
            status = "Copied to clipboard, but couldn't save \(out.lastPathComponent): \(error.localizedDescription)"
        }
    }
}

// MARK: - Window

struct ContentView: View {
    @Bindable var model: ReviewModel
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
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
            .background(Color(nsColor: .textBackgroundColor))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.open(url)
                return true
            }
            .inspector(isPresented: $showInspector) {
                CommentsInspector(model: model)
                    .inspectorColumnWidth(min: 250, ideal: 300, max: 420)
            }
        }
        .navigationTitle(model.fileURL?.lastPathComponent ?? "mdreview")
        .navigationSubtitle(model.fileURL.map { _ in "\(model.comments.count) comment\(model.comments.count == 1 ? "" : "s")" } ?? "")
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
                .help("Copy the review to the clipboard and save it beside the file (⌘↩)")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button("Comments", systemImage: "sidebar.right") { showInspector.toggle() }
            }
        }
        .alert("Couldn't open file", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.error ?? "")
        }
    }
}

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
                        Button { model.reveal(line: heading.line) } label: {
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
                            Button { model.reveal(comment) } label: {
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

struct CommentsInspector: View {
    @Bindable var model: ReviewModel
    @FocusState private var focusedField: ReviewComment.ID?

    var body: some View {
        VStack(spacing: 0) {
            if model.comments.isEmpty {
                ContentUnavailableView("No comments", systemImage: "text.bubble",
                                       description: Text("Select text in the document, then press ⌥⌘M or right-click → Add Comment."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array($model.comments.enumerated()), id: \.element.id) { index, $comment in
                            CommentCard(
                                number: index + 1,
                                comment: $comment,
                                isFocused: model.focusedComment == comment.id,
                                focusedField: $focusedField,
                                onSelect: { model.reveal(comment) },
                                onDelete: { model.delete(comment.id) }
                            )
                        }
                    }
                    .padding(12)
                }
            }
            if let status = model.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: model.focusedComment) { _, id in focusedField = id }
    }
}

struct CommentCard: View {
    let number: Int
    @Binding var comment: ReviewComment
    let isFocused: Bool
    var focusedField: FocusState<ReviewComment.ID?>.Binding
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("\(number)").font(.caption2.bold()).foregroundStyle(.white)
                    .frame(width: 18, height: 18).background(Circle().fill(.tint))
                Text("Line\(comment.lines.count == 1 ? "" : "s") \(comment.lineLabel)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete comment")
            }
            Text(comment.quote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(.tint).frame(width: 2) }
            TextField("Add a comment…", text: $comment.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused(focusedField, equals: comment.id)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isFocused ? Color.accentColor : Color.secondary.opacity(0.2)))
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Reader (opaque paper)

struct ReaderView: NSViewRepresentable {
    let text: NSAttributedString
    let comments: [ReviewComment]
    let focused: ReviewComment.ID?
    let scrollTarget: NSRange?
    let onSelect: @MainActor (NSRange) -> Void
    let onComment: @MainActor () -> Void
    let onScrolled: @MainActor @Sendable () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1 for simple layout-manager highlights and scrolling.
        let textView = PaperTextView(usingTextLayoutManager: false)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.usesFindBar = true
        textView.delegate = context.coordinator
        textView.unregisterDraggedTypes() // let file drops reach the SwiftUI drop target

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = coordinator.textView else { return }
        if coordinator.shownText !== text {
            textView.textStorage?.setAttributedString(text)
            coordinator.shownText = text
            textView.scroll(.zero)
        }
        coordinator.highlight(comments, focused: focused)
        if let target = scrollTarget {
            coordinator.reveal(target)
            DispatchQueue.main.async(execute: onScrolled)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderView?
        weak var textView: NSTextView?
        var shownText: NSAttributedString?

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView else { return }
            parent?.onSelect(textView.selectedRange())
        }

        func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
            let item = NSMenuItem(title: "Add Comment", action: #selector(addComment), keyEquivalent: "")
            item.target = self
            item.isEnabled = view.selectedRange().length > 0
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
            return menu
        }

        @objc func addComment() { parent?.onComment() }

        func highlight(_ comments: [ReviewComment], focused: ReviewComment.ID?) {
            guard let textView, let layout = textView.layoutManager else { return }
            let length = textView.textStorage?.length ?? 0
            let all = NSRange(location: 0, length: length)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
            for comment in comments where NSMaxRange(comment.range) <= length {
                layout.addTemporaryAttributes([
                    .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(comment.id == focused ? 0.32 : 0.16),
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .underlineColor: NSColor.controlAccentColor,
                ], forCharacterRange: comment.range)
            }
        }

        func reveal(_ range: NSRange) {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                  NSMaxRange(range) <= (textView.textStorage?.length ?? 0) else { return }
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            textView.scroll(NSPoint(x: 0, y: max(0, rect.minY + textView.textContainerOrigin.y - 24)))
            if range.length > 0 {
                textView.setSelectedRange(range)
                textView.showFindIndicator(for: range)
            }
        }
    }
}

/// Keeps a centered reading measure of about 720 pt however wide the window gets.
final class PaperTextView: NSTextView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        let inset = NSSize(width: max(40, (newSize.width - 720) / 2), height: 36)
        if textContainerInset != inset { textContainerInset = inset }
    }
}
