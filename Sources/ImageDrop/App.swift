// ImageDrop by deepquest | https://deepquest.code511.com/blog
import SwiftUI
import AppKit

@main
struct ImageDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("ImageDrop", id: "main") {
            ContentView(store: ConversionStore.shared)
                .frame(minWidth: 680, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ImageDrop") { Credits.showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button("deepquest Blog") { NSWorkspace.shared.open(Credits.url) }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Images…") { ConversionStore.shared.chooseFiles() }
                    .keyboardShortcut("o")
                Button("Choose Output Folder…") { ConversionStore.shared.chooseOutputFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Files or folders dropped onto the Dock icon (or "Open With → ImageDrop").
    func application(_ application: NSApplication, open urls: [URL]) {
        ConversionStore.shared.add(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Credits {
    static let author = "deepquest"
    static let url = URL(string: "https://deepquest.code511.com/blog")!

    @MainActor
    static func showAboutPanel() {
        let body = NSMutableAttributedString(
            string: "Created by \(author)\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: NSColor.labelColor])
        body.append(NSAttributedString(
            string: url.absoluteString,
            attributes: [.font: NSFont.systemFont(ofSize: 11), .link: url]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        body.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: body.length))

        NSApp.orderFrontStandardAboutPanel(options: [.credits: body])
        NSApp.activate(ignoringOtherApps: true)
    }
}
