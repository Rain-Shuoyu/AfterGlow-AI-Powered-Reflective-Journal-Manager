import Foundation
import SwiftUI
import AppKit

/// Holds the loaded diary entries + stats. Single source of truth for the UI.
/// Lives at the App level so it survives view switches.
@MainActor
final class DiaryStore: ObservableObject {
    @Published private(set) var entries: [DiaryEntry] = []
    @Published private(set) var stats: DiaryStats = .empty
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?
    /// Currently-loaded diary folder. The setter is what triggers a reload AND
    /// persists the path to UserDefaults, so the next launch auto-resumes
    /// where the user left off.
    @Published var folderURL: URL? {
        didSet {
            // Persist. We write to UserDefaults directly (not via AppSettings)
            // so this works even if the view that triggered the change is
            // the Stats view (which has no reference to SettingsStore).
            if let url = folderURL {
                UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastFolderKey)
            }
            reload()
        }
    }

    static let lastFolderKey = "DiaryInsight.lastFolderPath"

    init() {
        // Restore last folder on init. didSet doesn't fire during init in
        // Swift, so we manually call the reload after setting.
        if let path = UserDefaults.standard.string(forKey: Self.lastFolderKey),
           FileManager.default.fileExists(atPath: path) {
            self.folderURL = URL(fileURLWithPath: path)
        }
    }

    func reload() {
        guard let url = folderURL else {
            entries = []
            stats = .empty
            return
        }
        isLoading = true
        lastError = nil
        Task.detached(priority: .userInitiated) { [url] in
            do {
                let scanned = try DiaryScanner.shared.scan(folder: url)
                let computed = StatisticsEngine.compute(entries: scanned)
                await MainActor.run {
                    self.entries = scanned
                    self.stats = computed
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.entries = []
                    self.stats = .empty
                    self.lastError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    /// Show an open panel and let the user pick a folder. Returns the chosen URL,
    /// or nil if cancelled. The chosen path is auto-saved (via the folderURL
    /// didSet) so it'll be restored on next launch.
    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择日记目录"
        panel.message = "选择包含你的 Markdown 日记的文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            self.folderURL = url
        }
    }
}
