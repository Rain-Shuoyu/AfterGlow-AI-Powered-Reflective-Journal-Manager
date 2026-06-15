import Foundation
import SwiftUI

/// Local-only state for the "🕯 周年回响" banner.
///
/// Tracks:
///   - the most-recent date the banner was shown (so we only
///     show it once per anniversary window — not every cold start
///     inside 6/14-6/16)
///   - a "permanently disabled" flag (so the user can dismiss the
///     banner and never see it again)
@MainActor
final class AnniversaryStore: ObservableObject {

    private static let lastShownKey    = "DiaryInsight.Anniversary.lastShownDate"
    private static let disabledKey     = "DiaryInsight.Anniversary.userDisabled"
    private static let dismissedDatesKey = "DiaryInsight.Anniversary.dismissedDates"

    @Published private(set) var isUserDisabled: Bool
    @Published private(set) var lastShownDate: Date?
    @Published private(set) var dismissedDates: [String]   // yyyy-MM-dd strings

    init() {
        let d = UserDefaults.standard
        self.isUserDisabled = d.bool(forKey: Self.disabledKey)
        self.lastShownDate = d.object(forKey: Self.lastShownKey) as? Date
        self.dismissedDates = d.stringArray(forKey: Self.dismissedDatesKey) ?? []
    }

    /// Should the banner appear right now?
    /// Conditions:
    ///   1. User hasn't permanently disabled it.
    ///   2. There is at least one matching entry (i.e. some past
    ///      year had an entry on this same day-of-year).
    ///   3. We haven't shown the banner in the last 3 days
    ///      (anniversary window is day ± 1, so 3 days covers it).
    func shouldShowBanner(today: Date = Date(), entries: [DiaryEntry]) -> Bool {
        if isUserDisabled { return false }
        // Are we inside the anniversary window (today ± 1 day)?
        guard AnniversaryFinder.isInAnniversaryWindow(today) else { return false }
        // Is there at least one matching entry?
        let matches = AnniversaryFinder.find(in: entries, for: today)
        if matches.isEmpty { return false }
        // Have we already shown the banner in the last 3 days?
        if let last = lastShownDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: today).day ?? 999
            if days < 3 { return false }
        }
        // Has the user explicitly dismissed today's specific date?
        let key = dateKey(today)
        if dismissedDates.contains(key) { return false }
        return true
    }

    /// Mark the banner as shown right now.
    func markShown(today: Date = Date()) {
        lastShownDate = today
        UserDefaults.standard.set(today, forKey: Self.lastShownKey)
    }

    /// User dismissed for today (banner reappears tomorrow or next
    /// anniversary window).
    func dismissForToday(today: Date = Date()) {
        let key = dateKey(today)
        if !dismissedDates.contains(key) {
            dismissedDates.append(key)
            UserDefaults.standard.set(dismissedDates, forKey: Self.dismissedDatesKey)
        }
    }

    /// User toggled "never show me this banner" from settings.
    /// Mutates the published flag + persists.
    func setUserDisabled(_ disabled: Bool) {
        isUserDisabled = disabled
        UserDefaults.standard.set(disabled, forKey: Self.disabledKey)
    }

    /// Reset all state — useful for debugging or a "reset to
    /// defaults" affordance in Settings.
    func resetAll() {
        lastShownDate = nil
        dismissedDates = []
        isUserDisabled = false
        let d = UserDefaults.standard
        d.removeObject(forKey: Self.lastShownKey)
        d.removeObject(forKey: Self.dismissedDatesKey)
        d.removeObject(forKey: Self.disabledKey)
    }

    // MARK: - Helpers

    private func dateKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
