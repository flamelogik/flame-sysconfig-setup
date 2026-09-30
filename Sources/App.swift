// Flame Sysconfig Setup
// Guides the user through building a central Autodesk Flame sysconfig.cfg.

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

#if !TESTING
@main
struct SysconfigSetupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = ConfigModel()
    @State private var restored = false

    var body: some Scene {
        WindowGroup("Flame Sysconfig Setup") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 780, minHeight: 640)
                .onAppear {
                    guard !restored else { return }
                    restored = true
                    model.restoreLastSession()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                Button("Facility Profile…") { model.showProfileEditor = true }
                    .keyboardShortcut(",")
            }
        }
    }
}
#endif
