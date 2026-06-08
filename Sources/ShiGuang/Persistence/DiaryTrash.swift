import Foundation
import Combine

/// Soft-delete "recycle bin" for diary entries. When the user deletes an
/// entry we move its `.md` file to `~/Library/Application Support/
/// ShiGuang/Trash/` with a `<original>__<timestamp>.md` filename so
/// collisions are impossible. The user can browse the trash, restore
/// (back to the active diary folder) or permanently delete.
///
/// Persistence: just the filesystem. We don't keep a separate index
/// — every call to `refresh()` walks the directory and reads each
/// file's mtime. Cheap for the small number of trashed files a
/// person is realistically going to accumulate.
@MainActor
final class DiaryTrash: ObservableObject {
    static let shared = DiaryTrash()

    @Published private(set) var entries: [TrashedEntry] = []

    private let folder: URL
    private let fm = FileManager.default

    init() {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.folder = appSupport
            .appendingPathComponent("ShiGuang", isDirectory: true)
            .appendingPathComponent("Trash", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        refresh()
    }

    /// Absolute path of the trash directory. Useful for the "Reveal in
    /// Finder" button or for surfacing the path in the UI.
    var folderURL: URL { folder }

    // MARK: - Move into trash

    /// Move a diary file to the trash. Returns the new URL inside the
    /// trash, or `nil` on failure. Refreshes the entry list on success.
    @discardableResult
    func trash(fileURL: URL) -> URL? {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let stamp = Self.timestamp()
        let dest = folder.appendingPathComponent("\(baseName)__\(stamp).md")
        do {
            try fm.moveItem(at: fileURL, to: dest)
            refresh()
            return dest
        } catch {
            return nil
        }
    }

    // MARK: - Restore

    /// Move a trashed file back into `destinationFolder`. Filename
    /// collisions are auto-resolved (`-2`, `-3`, …).
    @discardableResult
    func restore(_ entry: TrashedEntry, to destinationFolder: URL) -> Bool {
        do {
            try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let dest = uniqueDestination(in: destinationFolder, baseName: entry.displayName)
            try fm.moveItem(at: entry.fileURL, to: dest)
            refresh()
            return true
        } catch {
            return false
        }
    }

    // MARK: - Permanent delete

    func permanentlyDelete(_ entry: TrashedEntry) {
        try? fm.removeItem(at: entry.fileURL)
        refresh()
    }

    func emptyTrash() {
        for entry in entries {
            try? fm.removeItem(at: entry.fileURL)
        }
        refresh()
    }

    // MARK: - Refresh

    /// Re-scan the trash directory and rebuild the `entries` list.
    /// Cheap; safe to call after any mutation or on view appear.
    func refresh() {
        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey, .fileSizeKey, .nameKey
        ]
        let urls = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys)
        )) ?? []
        let mdFiles = urls.filter { $0.pathExtension.lowercased() == "md" }

        let parsed: [TrashedEntry] = mdFiles.compactMap { url in
            let attrs = try? url.resourceValues(forKeys: resourceKeys)
            let filename = attrs?.name ?? url.lastPathComponent
            let date = attrs?.contentModificationDate ?? Date.distantPast
            let size = attrs?.fileSize ?? 0
            return TrashedEntry(
                id: url,
                fileURL: url,
                displayName: Self.parseOriginalName(from: filename),
                trashedAt: date,
                fileSize: size
            )
        }
        entries = parsed.sorted { $0.trashedAt > $1.trashedAt }
    }

    // MARK: - Helpers

    private func uniqueDestination(in folder: URL, baseName: String) -> URL {
        var candidate = folder.appendingPathComponent("\(baseName).md")
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            candidate = folder.appendingPathComponent("\(baseName)-\(n).md")
        }
        return candidate
    }

    private static func parseOriginalName(from filename: String) -> String {
        // Stored as `<original-name>__<timestamp>.md`. Strip the
        // extension, then split on the last `__` to get the original.
        let withoutExt = (filename as NSString).deletingPathExtension
        if let separatorRange = withoutExt.range(of: "__", options: .backwards) {
            return String(withoutExt[..<separatorRange.lowerBound])
        }
        return withoutExt
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        // Replace ":" with "-" so the filename is portable across
        // filesystems (Windows / network shares), even though we're
        // targeting macOS-only here.
        return f.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }
}

struct TrashedEntry: Identifiable, Hashable {
    let id: URL
    let fileURL: URL
    /// The diary's original filename without the timestamp suffix, e.g.
    /// `2026-06-07` for a file that was `2026-06-07__2026-06-07T22-19-23Z.md`.
    let displayName: String
    let trashedAt: Date
    let fileSize: Int
}
