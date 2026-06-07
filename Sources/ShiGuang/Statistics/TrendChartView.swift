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
                    .foregroundStyle(DS.Brand.amber)
                }
                if monthly.contains(where: { $0.averageMood != nil }) {
                    ForEach(monthly.filter { $0.averageMood != nil }) { m in
                        LineMark(
                            x: .value("Month", label(for: m)),
                            y: .value("Mood", (m.averageMood ?? 3) * 1000)
                        )
                        .foregroundStyle(Color(red: 0.78, green: 0.45, blue: 0.55))
                        .symbol {
                            Circle()
                                .fill(Color(red: 0.78, green: 0.45, blue: 0.55))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
            }
            .chartLegend(.visible)
            .chartForegroundStyleScale([
                "字数":   DS.Brand.amber,
                "平均情绪": Color(red: 0.78, green: 0.45, blue: 0.55)
            ])
            .frame(minHeight: 220)
        }
    }

    private func label(for m: MonthlyMetric) -> String {
        String(format: "%d-%02d", m.year, m.month)
    }
}
