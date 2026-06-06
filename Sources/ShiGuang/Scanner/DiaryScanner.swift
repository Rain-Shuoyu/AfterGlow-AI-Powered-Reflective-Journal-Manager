import Foundation

/// Walks a folder looking for `.md` / `.markdown` files and parses each into a `DiaryEntry`.
final class DiaryScanner: @unchecked Sendable {
    static let shared = DiaryScanner()

    private let fileManager = FileManager.default

    /// Recursively scan a folder for diary files. Hidden files / folders are skipped.
    /// - Returns: parsed entries, sorted by date descending.
    func scan(folder: URL) throws -> [DiaryEntry] {
        let files = try collectMarkdownFiles(in: folder)
        var entries: [DiaryEntry] = []
        entries.reserveCapacity(files.count)
        for url in files {
            if let entry = try? DiaryParser.parse(file: url) {
                entries.append(entry)
            }
        }
        return entries.sorted { $0.date > $1.date }
    }

    private func collectMarkdownFiles(in folder: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScannerError.cannotEnumerate(folder.path)
        }

        var results: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey])
            if values.isHidden == true { continue }
            guard values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            if ext == "md" || ext == "markdown" {
                results.append(url)
            }
        }
        return results
    }

    enum ScannerError: LocalizedError {
        case cannotEnumerate(String)
        var errorDescription: String? {
            switch self {
            case .cannotEnumerate(let p): return "无法扫描目录：\(p)"
            }
        }
    }
}
