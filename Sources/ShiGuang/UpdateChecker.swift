import Foundation

/// Checks the GitHub releases API for a newer version of the app.
///
/// Uses the public (unauthenticated) endpoint — rate limit is 60
/// requests/hour per IP, which is plenty for a manual "check for
/// updates" button. If we ever want background polling, we'd
/// attach the GitHub token here.
enum UpdateChecker {

    /// Where to look for releases. Hard-coded for now; could become
    /// a setting later.
    static let repoOwner = "Rain-Shuoyu"
    static let repoName  = "AfterGlow-AI-Powered-Reflective-Journal-Manager"

    /// Result of a single check.
    enum Status: Equatable {
        /// Running state — not user-facing; set briefly while in flight.
        case checking
        /// No newer version found.
        case upToDate(current: String, latest: String)
        /// Newer version is available; `url` is the release page.
        case updateAvailable(current: String, latest: String, url: URL)
        /// Network / parse / unexpected error. `message` is a
        /// human-readable hint for the user.
        case error(String)
    }

    /// Current version string, e.g. "0.1.0". Read from the bundle's
    /// Info.plist (set by `build-app.sh`).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Hit the GitHub releases API and return a `Status`. Async —
    /// safe to call from `Task { ... }` in the SwiftUI layer.
    static func check() async -> Status {
        let url = URL(string:
            "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        )!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub recommends a UA for unauthenticated API calls; some
        // endpoints reject blank UAs.
        req.setValue("ShiGuang/0.1 (+https://github.com/\(repoOwner)/\(repoName))",
                     forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .error("无 HTTP 响应")
            }
            // 403/429 = rate limit, 404 = no releases yet, others = generic
            if http.statusCode == 403 || http.statusCode == 429 {
                return .error("GitHub API 限流（60 次/小时），稍后再试")
            }
            if http.statusCode == 404 {
                return .error("还没发过 release")
            }
            guard (200..<300).contains(http.statusCode) else {
                return .error("HTTP \(http.statusCode)")
            }
            // Decode just the fields we need
            struct Release: Decodable {
                let tag_name: String
                let html_url: String
                let draft: Bool
                let prerelease: Bool
            }
            let r = try JSONDecoder().decode(Release.self, from: data)
            // Skip drafts and pre-releases — they're not for end users.
            if r.draft || r.prerelease {
                return .error("最新版本是预发布，不算正式更新")
            }
            let current = currentVersion
            let latest  = r.tag_name.hasPrefix("v")
                ? String(r.tag_name.dropFirst())
                : r.tag_name
            // Version comparison: split by `.` and compare as integers.
            // "0.1" < "0.2" → 0=0, 1<2. "1.0.0" > "0.9.9" → 1>0.
            if compareVersions(latest, current) > 0 {
                return .updateAvailable(
                    current: current,
                    latest: latest,
                    url: URL(string: r.html_url) ?? URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!
                )
            } else {
                return .upToDate(current: current, latest: latest)
            }
        } catch let urlErr as URLError {
            return .error("网络错误：\(urlErr.localizedDescription)")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    /// Returns positive if `a` is newer than `b`, negative if older,
    /// zero if equal. Pads missing components with 0 so "0.1" ==
    /// "0.1.0".
    static func compareVersions(_ a: String, _ b: String) -> Int {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        let n = max(aParts.count, bParts.count)
        for i in 0..<n {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x - y }
        }
        return 0
    }
}
