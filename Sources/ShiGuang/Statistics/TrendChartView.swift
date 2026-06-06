import SwiftUI
import Charts

/// Monthly word-count bar chart with an optional line overlay for average mood.
struct TrendChartView: View {
    let monthly: [MonthlyMetric]

    var body: some View {
        if monthly.isEmpty {
            Text("还没有数据")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            Chart {
                ForEach(monthly) { m in
                    BarMark(
                        x: .value("Month", label(for: m)),
                        y: .value("Words", m.wordCount)
                    )
                    .foregroundStyle(by: .value("Series", "字数"))
                }
                if monthly.contains(where: { $0.averageMood != nil }) {
                    ForEach(monthly.filter { $0.averageMood != nil }) { m in
                        LineMark(
                            x: .value("Month", label(for: m)),
                            y: .value("Mood", (m.averageMood ?? 3) * 1000)
                        )
                        .foregroundStyle(by: .value("Series", "情绪(×1000)"))
                        .symbol(by: .value("Series", "情绪(×1000)"))
                    }
                }
            }
            .chartLegend(.visible)
            .frame(minHeight: 220)
        }
    }

    private func label(for m: MonthlyMetric) -> String {
        String(format: "%d-%02d", m.year, m.month)
    }
}
