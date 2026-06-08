import Foundation
import SwiftUI

/// Shared state for the "check for updates" flow. Lifted out of
/// `SettingsView` so the launch screen can kick off a check on
/// startup and the user sees the cached result by the time they
/// navigate to the settings tab.
///
/// ## Throttling
///
/// We throttle *automatic* checks (the one the launch screen fires
/// on every cold start) to **once per 12 hours**. The throttle is
/// persistent — `lastAutomaticCheck` lives in UserDefaults so it
/// survives app restarts. Manual checks triggered from the
/// Settings UI **bypass** the throttle (the user explicitly asked,
/// so we hit the API regardless).
@MainActor
final class UpdateStore: ObservableObject {

    /// Minimum interval between *automatic* checks. The launch
    /// screen waits this long before the next auto check will
    /// actually hit the network.
    private static let automaticInterval: TimeInterval = 12 * 60 * 60

    /// UserDefaults key for the persisted timestamp. Surfaced as
    /// a static so tests / debug menus can poke it.
    static let lastAutomaticCheckKey = "DiaryInsight.UpdateStore.lastAutomaticCheck"

    /// Result of the most recent (or in-flight) check. `nil` means
    /// we haven't checked yet this session.
    @Published private(set) var status: UpdateChecker.Status?
    @Published private(set) var isChecking: Bool = false

    /// Bumped every time we kick off a new check. Used to ignore
    /// late results from earlier requests when the user clicks
    /// repeatedly.
    @Published private(set) var runId: Int = 0

    /// Timestamp of the last automatic check that actually hit the
    /// network (skipped-throttle attempts don't update this).
    /// Loaded from UserDefaults on init so a fresh launch honours
    /// the cooldown.
    @Published private(set) var lastAutomaticCheck: Date?

    init() {
        if let stored = UserDefaults.standard.object(forKey: Self.lastAutomaticCheckKey) as? Date {
            self.lastAutomaticCheck = stored
        }
    }

    /// Read-only convenience: the version baked into the running bundle.
    var currentVersion: String { UpdateChecker.currentVersion }

    /// Human-readable "when did the last automatic check happen".
    /// Drives the helper text under the status row in Settings.
    var lastAutomaticCheckDescription: String? {
        guard let when = lastAutomaticCheck else { return nil }
        let secs = Int(Date().timeIntervalSince(when))
        if secs < 60 { return "刚刚自动检查过" }
        if secs < 3600 { return "上次自动检查：\(secs / 60) 分钟前" }
        if secs < 24 * 3600 { return "上次自动检查：\(secs / 3600) 小时前" }
        return "上次自动检查：\(secs / 86400) 天前"
    }

    /// Called by the launch screen. Respects the 12h throttle;
    /// manual `check()` calls bypass it.
    func checkAutomatically() {
        if let last = lastAutomaticCheck {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < Self.automaticInterval {
                // Within cooldown. Don't touch the network, don't
                // bump the timestamp — the user is just going to
                // see the cached status from the previous run.
                return
            }
        }
        recordAutomaticCheckTimestamp()
        check()
    }

    /// Manual entry point. Called from the Settings button. Always
    /// hits the network, regardless of how long ago the last
    /// automatic check was.
    func check() {
        runId += 1
        let thisRun = runId
        isChecking = true
        status = .checking
        Task { @MainActor [weak self] in
            let result = await UpdateChecker.check()
            guard let self else { return }
            // If another check started after us, drop this stale result.
            guard self.runId == thisRun else { return }
            self.status = result
            self.isChecking = false
        }
    }

    private func recordAutomaticCheckTimestamp() {
        let now = Date()
        lastAutomaticCheck = now
        UserDefaults.standard.set(now, forKey: Self.lastAutomaticCheckKey)
    }
}
