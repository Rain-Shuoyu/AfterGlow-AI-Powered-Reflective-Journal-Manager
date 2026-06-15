import SwiftUI

/// "🕯 周年回响" sheet — displays diary entries written on the
/// same day-of-year in past years.
///
/// The sheet is *passive*: it shows the past entries with date
/// headers + a preview, and lets the user tap to open the full
/// entry. It deliberately does NOT add commentary, advice, or
/// LLM-generated reflection — that's the job of "回溯" (already
/// in v0.1.2). This sheet's purpose is to surface time itself.
struct AnniversarySheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var diaryStore: DiaryStore

    /// The set of past entries for today.
    let entries: [AnniversaryEntry]

    /// Tapping a card sets this so we can open the full entry
    /// sheet for it.
    @State private var selectedEntry: DiaryEntry?

    init(entries: [AnniversaryEntry]) {
        self.entries = entries
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(spacing: 20) {
                    if entries.isEmpty {
                        emptyState
                    } else {
                        ForEach(entries) { ae in
                            anniversaryCard(ae)
                        }
                        footer
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
        }
        .frame(width: 620, height: 600)
        .background {
            ZStack {
                Color(white: 0.07)
                // Warm candle glow at top
                RadialGradient(
                    colors: [DS.Brand.amber.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.5, y: 0.0),
                    startRadius: 0,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedEntry) { entry in
            DiaryDetailSheet(entry: entry)
                .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 680)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("🕯")
                        .font(.system(size: 18))
                    Text("周年回响")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var headerSubtitle: String {
        if entries.isEmpty {
            return "你的今天值得被记住"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        let today = f.string(from: Date())
        let years = entries.map { $0.yearsAgo }
        let yearsList = formatYears(years)
        return "\(today) · 你已走过 \(yearsList)"
    }

    private func formatYears(_ years: [Int]) -> String {
        let sorted = years.sorted()
        // Build "1 年 / 2 年 / 3 年"
        return sorted.map { "\($0) 年" }.joined(separator: "、")
    }

    // MARK: - Anniversary card

    private func anniversaryCard(_ ae: AnniversaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("🕯")
                    .font(.system(size: 14))
                Text("\(ae.yearsAgo) 年前的今天")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Brand.amber)
                Spacer()
                Text(formattedFullDate(ae.entry.date))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Brand.warmGray)
            }
            Text(ae.preview)
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(.white.opacity(0.85))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    selectedEntry = ae.entry
                } label: {
                    HStack(spacing: 4) {
                        Text("打开完整日记")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(DS.Brand.amber)
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
                        .stroke(DS.Brand.amber.opacity(0.18), lineWidth: 0.5)
                )
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🕯")
                .font(.system(size: 40))
                .opacity(0.5)
            Text("往年的今天还没有日记。")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Text("继续写，未来某年的今天会再回来。")
                .font(.caption)
                .foregroundStyle(DS.Brand.warmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 6) {
            Text("时间会回来。")
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(DS.Brand.warmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func formattedFullDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
