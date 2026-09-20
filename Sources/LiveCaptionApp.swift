import AppKit
import SwiftUI

@main
struct LiveCaptionApp: App {
    @StateObject private var model = CaptionViewModel()

    init() {
        AppHangWatchdog.shared.start()
    }

    var body: some Scene {
        Window("LiveCaption", id: "caption") {
            CaptionPanel(model: model)
        }
        .defaultSize(width: 340, height: 108)
        .windowStyle(.plain)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("剪切") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x")
                Button("复制") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c")
                Button("粘贴") {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("v")
                Divider()
                Button("全选") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a")
            }
        }

        MenuBarExtra("LiveCaption", systemImage: model.recording.isRecording
                     ? "record.circle.fill"
                     : (model.capture.isRunning ? "captions.bubble.fill" : "captions.bubble")) {
            MenuBarMenu(model: model)
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
