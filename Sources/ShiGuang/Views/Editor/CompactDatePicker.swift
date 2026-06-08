import SwiftUI

/// Custom compact calendar. Used in the date-picker popover instead of
/// SwiftUI's `.graphical` `DatePicker`, which renders inside a much
/// bigger chrome frame on macOS (lots of dead space around a tiny
/// calendar grid). This is a single-month grid with prev/next nav,
/// ~290pt wide, sized exactly to its contents.
struct CompactDatePicker: View {
    @Binding var date: Date
    @State private var displayedMonth: Date

    init(date: Binding<Date>) {
        self._date = date
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date.wrappedValue)
        self._displayedMonth = State(initialValue: cal.date(from: comps) ?? date.wrappedValue)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.s) {
            monthHeader
            weekdayHeader
            dayGrid
        }
        .padding(12)
    }

    // MARK: - Sub-views

    private var monthHeader: some View {
        HStack {
            Button { shiftMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthYearString)
                .font(.callout.weight(.semibold))
                .monospacedDigit()

            Spacer()

            Button { shiftMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        let cells = monthCells()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(0..<cells.count, id: \.self) { i in
                if let day = cells[i] {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 30)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: date)
        let isToday = cal.isDateInToday(day)
        return Button {
            // Selecting a day also closes the popover (handled by the
            // parent — it observes `date` and sets showDatePopover = false).
            date = day
        } label: {
            Text("\(cal.component(.day, from: day))")
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background {
                    if isSelected {
                        Circle().fill(DS.Brand.amber)
                    } else if isToday {
                        Circle().strokeBorder(DS.Brand.amber, lineWidth: 1)
                    }
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date math

    private var monthYearString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月"
        return f.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f.veryShortStandaloneWeekdaySymbols   // ["日","一","二",...]
    }

    /// Returns 42 cells (6 weeks × 7 days) for the displayed month.
    /// Leading nil cells fill the offset from Monday so the grid always
    /// starts on a Monday. Trailing nils pad the last week.
    private func monthCells() -> [Date?] {
        let cal = Calendar.current
        let range = cal.range(of: .day, in: .month, for: displayedMonth) ?? 1..<29
        let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))!
        let weekdayOfFirst = cal.component(.weekday, from: firstDay)   // 1 = Sunday
        // Convert to Monday-first offset: 0 = Monday
        let leadingBlanks = (weekdayOfFirst + 5) % 7

        var cells: [Date?] = []
        for _ in 0..<leadingBlanks { cells.append(nil) }
        for d in range {
            if let day = cal.date(byAdding: .day, value: d - 1, to: firstDay) {
                cells.append(day)
            }
        }
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private func shiftMonth(_ delta: Int) {
        if let new = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = new
        }
    }
}
