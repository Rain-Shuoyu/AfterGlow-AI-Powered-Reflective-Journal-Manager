import Foundation

/// Parses a single markdown file into a `DiaryEntry`:
///   1. Splits off YAML frontmatter (between `---` fences at file top).
///   2. Reads date from frontmatter `date:` (ISO 8601 / yyyy-MM-dd) or from filename.
///   3. Reads mood (1-5) and mood label from frontmatter.
///   4. Falls back to the first markdown heading, then the filename, for the title.
enum DiaryParser {
    static func parse(file url: URL) throws -> DiaryEntry {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let (frontmatterRaw, body) = splitFrontmatter(raw)

        let fm = parseFrontmatter(frontmatterRaw)

        let filename = url.deletingPathExtension().lastPathComponent
        let date = fm.date ?? parseDate(from: filename) ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let title = fm.title ?? firstHeading(in: body) ?? filename

        let plainBody = body
        let wc = countWords(in: plainBody)

        let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])

        let id = stableID(for: url)
        return DiaryEntry(
            id: id,
            url: url,
            date: date,
            title: title,
            rawContent: plainBody,
            frontmatter: fm,
            wordCount: wc,
            characterCount: plainBody.count,
            createdAt: attrs?.creationDate,
            modifiedAt: attrs?.contentModificationDate
        )
    }

    // MARK: - Frontmatter split

    private static func splitFrontmatter(_ raw: String) -> (String, String) {
        let trimmed = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard trimmed.hasPrefix("---") else { return ("", raw) }
        let lines = trimmed.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return ("", raw) }
        // find closing fence
        var endIndex: Int? = nil
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return ("", raw) }
        let fm = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (fm, body)
    }

    // MARK: - Frontmatter parse (intentionally small + forgiving)

    static func parseFrontmatter(_ raw: String) -> Frontmatter {
        guard !raw.isEmpty else { return .empty }
        var fm = Frontmatter.empty
        var extra: [String: String] = [:]

        let knownKeys: Set<String> = ["mood", "mood_label", "moodLabel", "weather", "tags", "title", "date"]
        let lines = raw.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // list under a key (e.g. `tags:` followed by `- a` / `- b`)
            if let m = line.range(of: #"^([A-Za-z0-9_\-]+):\s*$"#, options: .regularExpression) {
                _ = m
                let key = String(line.split(separator: ":").first ?? "").lowercased()
                if knownKeys.contains(key) {
                    var collected: [String] = []
                    var j = i + 1
                    while j < lines.count {
                        let l = lines[j]
                        if let itemMatch = l.range(of: #"^\s*-\s+(.+)$"#, options: .regularExpression) {
                            let item = String(l[itemMatch])
                                .replacingOccurrences(of: #"^\s*-\s+"#, with: "", options: .regularExpression)
                                .trimmingCharacters(in: .whitespaces)
                            collected.append(item)
                            j += 1
                        } else { break }
                    }
                    applyListValue(key: key, values: collected, into: &fm)
                    i = j
                    continue
                }
            }
            // simple `key: value` (or `key: value with: colons`)
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).lowercased().trimmingCharacters(in: .whitespaces)
                let rawValue = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                let value = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if !key.isEmpty && !value.isEmpty {
                    applyScalarValue(key: key, value: value, into: &fm, extra: &extra)
                }
            }
            i += 1
        }
        fm.extra = extra
        return fm
    }

    private static func applyScalarValue(key: String, value: String, into fm: inout Frontmatter, extra: inout [String: String]) {
        switch key {
        case "mood":
            if let n = Int(value.split(separator: "/").first.map(String.init) ?? value) {
                fm.mood = max(1, min(5, n))
            } else if let n = Double(value) {
                fm.mood = max(1, min(5, Int(n.rounded())))
            }
        case "mood_label", "moodlabel":
            fm.moodLabel = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        case "weather":
            fm.weather = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        case "title":
            fm.title = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        case "date":
            fm.date = parseDate(from: value)
        default:
            extra[key] = value
        }
    }

    private static func applyListValue(key: String, values: [String], into fm: inout Frontmatter) {
        switch key {
        case "tags":
            fm.tags = values
        default:
            break
        }
    }

    // MARK: - Helpers

    private static func firstHeading(in body: String) -> String? {
        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let m = line.range(of: #"^#{1,6}\s+(.+)$"#, options: .regularExpression) {
                let title = String(line[m])
                    .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }

    static func parseDate(from string: String) -> Date? {
        let s = string.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }

        let formats = [
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        ]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        for f in formats {
            df.dateFormat = f
            if let d = df.date(from: s) { return d }
        }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: s) { return d }
        return nil
    }

    static func countWords(in text: String) -> Int {
        // CJK characters count as one "word" each. Latin / Cyrillic / Greek runs
        // (letters + digits) count as one word per run. Other scripts fall into
        // the per-character bucket. Approximation that's good enough for diary stats.
        var count = 0
        var inAlnum = false
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                count += 1
                inAlnum = false
            } else if CharacterSet.alphanumerics.contains(scalar) {
                if !inAlnum {
                    inAlnum = true
                    count += 1
                }
            } else {
                inAlnum = false
            }
        }
        return count
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v)            // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(v)            // CJK Ext A
            || (0x20000...0x2A6DF).contains(v)          // CJK Ext B
            || (0x3040...0x309F).contains(v)            // Hiragana
            || (0x30A0...0x30FF).contains(v)            // Katakana
            || (0xAC00...0xD7AF).contains(v)            // Hangul
    }

    private static func stableID(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
