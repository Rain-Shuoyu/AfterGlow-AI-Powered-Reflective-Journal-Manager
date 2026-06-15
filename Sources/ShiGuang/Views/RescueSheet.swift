import SwiftUI

/// "🌧 你之前走过这段路" sheet — when the rescue signal is
/// strong, show 1-2 past diary entries from 6-12 months ago
/// where the user was in a similar low-mood state.
///
/// The sheet is *passive on purpose*: it does not add LLM
/// commentary, advice, or motivational language. It just
/// surfaces the user's own past writing as a quiet reminder
/// "you've been here before, and you came out the other side".
struct RescueSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var diaryStore: DiaryStore
    @EnvironmentObject var rescueStore: RescueStore

    let signal: RescueSignal

    @State private var selectedEntry: DiaryEntry?
    @State private var rescuedEntries: [DiaryEntry] = []
    @State private var showPermanentDismissConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if rescuedEntries.isEmpty {
                        emptyState
                    } else {
                        intro
                        ForEach(rescuedEntries) { e in
                            entryCard(e)
                        }
                        footerActions
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 600, height: 580)
        .background {
            ZStack {
                Color(white: 0.07)
                // Cool blue-ish glow (vs the warm amber of other sheets)
                RadialGradient(
                    colors: [
                        Color(red: 0.45, green: 0.55, blue: 0.65).opacity(0.10),
                        .clear
                    ],
                    center: UnitPoint(x: 0.5, y: 0.15),
                    startRadius: 0,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedEntry) { entry in
            DiaryDetailSheet(entry: entry)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
        .alert("不再显示这个？", isPresented: $showPermanentDismissConfirm) {
            Button("取消", role: .cancel) {}
            Button("不再显示", role: .destructive) {
                rescueStore.permanentDismiss()
                dismiss()
            }
        } message: {
            Text("你可以随时在 设置 里重新打开。")
        }
        .onAppear {
            recomputeRescued()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("🌧")
                        .font(.system(size: 18))
                    Text("你之前走过这段路")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.65, green: 0.75, blue: 0.85).opacity(0.85))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var headerSubtitle: String {
        if signal.level == .intervene {
            return "你最近说过的话，我想你可能需要回顾一下"
        }
        return "过去 \(signal.daysAffected) 天你都不太好。这些是之前类似的时刻"
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(introLine)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private var introLine: String {
        switch signal.level {
        case .intervene:
            return "你最近写了些很重的话。半年前你也走过这段路。下面是你当时写的——你写完之后，还继续走下去了。"
        case .watch:
            return "你最近几天都提不起劲。下面这些是你之前也不太好的时候写的——你后来还是走出来了。"
        case .none:
            return ""
        }
    }

    // MARK: - Entry card

    private func entryCard(_ e: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(formattedDate(e.date))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.65, green: 0.75, blue: 0.85))
                Spacer()
                if let mood = e.frontmatter.mood {
                    HStack(spacing: 2) {
                        ForEach(0..<mood, id: \.self) { _ in
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(DS.Brand.amber.opacity(0.7))
                        }
                    }
                }
            }
            Text(makePreview(from: e))
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    selectedEntry = e
                } label: {
                    HStack(spacing: 4) {
                        Text("打开完整日记")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.65, green: 0.75, blue: 0.85))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.45, green: 0.55, blue: 0.65).opacity(0.25), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 8) {
            Text("不需要做任何事。可以只是看一会儿。")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(DS.Brand.warmGray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button {
                showPermanentDismissConfirm = true
            } label: {
                Text("我不想再看到这个")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🌧")
                .font(.system(size: 36))
                .opacity(0.5)
            Text("还没有可以回顾的日记。")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Text("继续写，未来某天它们会回来。")
                .font(.caption)
                .foregroundStyle(DS.Brand.warmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private func recomputeRescued() {
        let cal = Calendar.current
        let today = Date()
        // Window: 6-12 months ago, OR up to 2 years back as a
        // very-loose fallback.
        guard let sixMo = cal.date(byAdding: .month, value: -6, to: today),
              let twelveMo = cal.date(byAdding: .month, value: -12, to: today),
              let twoYearsAgo = cal.date(byAdding: .year, value: -2, to: today)
        else { return }
        // Try 6-12 months first.
        let candidates = diaryStore.entries
            .filter { e in
                e.date >= twelveMo && e.date <= sixMo
            }
            .filter { e in
                // Look for low mood
                if let m = e.frontmatter.mood, m <= 2 { return true }
                if let mq = RescueDetector.parseMoodQuick(from: e), mq.score <= 2 {
                    return true
                }
                return false
            }
            .sorted { $0.date < $1.date }
        if !candidates.isEmpty {
            // Take up to 2 entries, spread across the window
            rescuedEntries = Array(candidates.prefix(2))
            return
        }
        // Fallback: 1-2 years ago, low mood
        let older = diaryStore.entries
            .filter { e in
                e.date >= twoYearsAgo && e.date < twelveMo
            }
            .filter { e in
                if let m = e.frontmatter.mood, m <= 2 { return true }
                if let mq = RescueDetector.parseMoodQuick(from: e), mq.score <= 2 {
                    return true
                }
                return false
            }
            .sorted { $0.date < $1.date }
        rescuedEntries = Array(older.prefix(2))
    }

    private func makePreview(from e: DiaryEntry) -> String {
        let raw = e.rawContent
        let paragraphs = raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let head = paragraphs.prefix(2).joined(separator: "\n\n")
        if head.count <= 280 { return head }
        let end = head.index(head.startIndex, offsetBy: 280)
        return String(head[..<end]) + "…"
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日"
        return f.string(from: d)
    }
}
