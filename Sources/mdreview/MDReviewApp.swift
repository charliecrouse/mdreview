import SwiftUI

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
            SidebarCommands()
            InspectorCommands()
            CommandGroup(replacing: .newItem) {
                Button("Open…") { model.showOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Review") {
                Button("Add Comment") { model.addComment() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                    .disabled(!model.canComment)
                Button("Add Page Comment") { model.addPageComment() }
                    .keyboardShortcut("m", modifiers: [.command, .option, .shift])
                    .disabled(model.fileURL == nil)
                Button("Next Comment") { model.step(by: 1) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .control])
                    .disabled(model.visibleComments.isEmpty)
                Button("Previous Comment") { model.step(by: -1) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .control])
                    .disabled(model.visibleComments.isEmpty)
                Divider()
                Button(model.agentWaiting ? "Send to Waiting Agent" : "Send to Agent") { model.send() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.comments.isEmpty)
            }
        }
    }
}
