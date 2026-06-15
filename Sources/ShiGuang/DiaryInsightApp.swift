import SwiftUI
import AppKit

@main
struct ShiGuangApp: App {
    @StateObject private var store = DiaryStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var updateStore = UpdateStore()
    @StateObject private var practiceStore = DailyPracticeStore()
    @StateObject private var anniversaryStore = AnniversaryStore()
    @StateObject private var rescueStore = RescueStore()

    init() {
        // CLI sanity-check mode: `DiaryInsight --sanity-check <folder>`
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--sanity-check"), idx + 1 < args.count {
            let path = args[idx + 1]
            SanityCheck.run(folder: URL(fileURLWithPath: path))
            exit(0)
        }
        // Make sure the app shows up as a regular GUI app even when launched from
        // `swift run` (where the executable would otherwise inherit a non-activating
        // LSUIElement-ish behavior). No-op when launched from a real .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(settingsStore)
                .environmentObject(updateStore)
                .environmentObject(practiceStore)
                .environmentObject(anniversaryStore)
                .environmentObject(rescueStore)
                // DiaryStore.init() already restores the last folder from
                // UserDefaults — no manual onAppear wiring needed.
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("选择日记目录…") { store.pickFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

