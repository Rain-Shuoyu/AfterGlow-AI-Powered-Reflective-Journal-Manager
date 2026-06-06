import SwiftUI

/// GitHub-style contribution heatmap. Renders the last `weeks` weeks (default 52)
/// of daily word counts, with intensity scaled to the busiest day in the window.
struct HeatmapView: View {
    let metrics: [DailyMetric]
    var weeks: Int = 52
    var cellSize: CGFloat = 12
    var cellSpacing: CGFloat = 3

    private var grid: HeatmapGrid {
        HeatmapGrid.build(metrics: metrics, weeks: weeks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: cellSpacing) {
                weekdayLabels
                ForEach(grid.columns) { col in
                    VStack(spacing: cellSpacing) {
                        ForEach(0..<7, id: \.self) { row in
                            cell(for: row, in: col)
                        }
                    }
                }
            }
            legend
        }
    }

    private var weekdayLabels: some View {
        VStack(spacing: cellSpacing) {
            ForEach(["", "Mon", "", "Wed", "", "Fri", ""], id: \.self) { s in
                Text(s)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: cellSize, alignment: .trailing)
            }
        }
    }

    private func cell(for row: Int, in col: HeatmapColumn) -> some View {
        let day = col.days[row]
        let intensity = day.map { grid.intensity(for: $0) } ?? 0
        return RoundedRectangle(cornerRadius: 2)
            .fill(color(forIntensity: intensity))
            .frame(width: cellSize, height: cellSize)
            .help(tooltip(for: day))
    }

    private func tooltip(for day: DailyMetric?) -> String {
        guard let d = day else { return "no entry" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        var s = "\(df.string(from: d.date)) — \(d.wordCount) words"
        if let mood = d.mood { s += " · mood \(mood)/5" }
        return s
    }

    private func color(forIntensity i: Double) -> Color {
        // 0..1 scale
        let base: [Color] = [
            Color(nsColor: .controlBackgroundColor),
            Color(red: 0.78, green: 0.90, blue: 0.78),
            Color(red: 0.50, green: 0.80, blue: 0.50),
            Color(red: 0.22, green: 0.62, blue: 0.30),
            Color(red: 0.10, green: 0.46, blue: 0.18)
        ]
        if i <= 0 { return base[0] }
        let idx = max(1, min(base.count - 1, Int(ceil(i * Double(base.count - 1)))))
        return base[idx]
    }

    private var legend: some View {
        HStack(spacing: 6) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(forIntensity: Double(i) / 4.0))
                    .frame(width: 12, height: 12)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grid layout

struct HeatmapColumn: Identifiable {
    let id: Int                // column index
    let days: [DailyMetric?]   // 7 entries, index 0 = Sunday (or per locale)
}

struct HeatmapGrid {
    let columns: [HeatmapColumn]
    private let maxWords: Int

    static func build(metrics: [DailyMetric], weeks: Int) -> HeatmapGrid {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // start on the most recent Sunday (column-aligned)
        let weekday = cal.component(.weekday, from: today)   // 1 = Sunday
        let daysSinceSunday = weekday - 1
        let endDay = cal.date(byAdding: .day, value: -daysSinceSunday, to: today) ?? today
        let startDay = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: endDay) ?? endDay

        let metricByDay: [Date: DailyMetric] = Dictionary(
            uniqueKeysWithValues: metrics.map { (cal.startOfDay(for: $0.date), $0) }
        )

        var cols: [HeatmapColumn] = []
        var cursor = startDay
        for col in 0..<weeks {
            var colDays: [DailyMetric?] = []
            for _ in 0..<7 {
                colDays.append(metricByDay[cursor])
                cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            }
            cols.append(HeatmapColumn(id: col, days: colDays))
        }
        let maxW = max(1, metrics.map(\.wordCount).max() ?? 1)
        return HeatmapGrid(columns: cols, maxWords: maxW)
    }

    func intensity(for day: DailyMetric) -> Double {
        guard day.wordCount > 0 else { return 0 }
        return min(1.0, Double(day.wordCount) / Double(maxWords))
    }
}
