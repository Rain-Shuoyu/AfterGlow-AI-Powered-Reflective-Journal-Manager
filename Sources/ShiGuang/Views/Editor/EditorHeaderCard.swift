import SwiftUI

/// Header card at the top of the editor — surfaces the frontmatter fields:
/// date, mood (1-5), title, tags, weather. Styled as a glass card so the
/// structure is visible at a glance without competing visually with the
/// actual diary body.
struct EditorHeaderCard: View {
    @Binding var state: EditorState
    @State private var showDatePopover: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            // Row 1: date button (custom-styled, opens a graphical calendar
            // popover) + weather on the right
            HStack(spacing: DS.Spacing.m) {
                dateButton
                Divider().frame(height: 22)
                weatherField
                Spacer(minLength: 0)
            }

            // Row 2: mood (1-5) + "AI 决定" affordance
            moodRow

            // Row 3: title
            titleField

            // Row 4: tags
            tagsRow
        }
        .padding(DS.Spacing.l)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        }
    }

    // MARK: - Date (custom button + popover)

    private var dateButton: some View {
        Button {
            showDatePopover.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.callout)
                    .foregroundStyle(DS.Brand.amber)
                Text(formattedDate(state.date))
                    .font(.callout.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(minWidth: 200)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Brand.amber.opacity(0.10))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.Brand.amber.opacity(0.30), lineWidth: 0.6)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) {
            // Custom compact calendar — wider (320pt) so each day cell
            // is ~40pt and easy to click. SwiftUI's `.graphical` DatePicker
            // wraps a tiny calendar in a huge chrome frame; this is sized
            // exactly to its contents.
            CompactDatePicker(date: $state.date)
                .frame(width: 320)
                .padding(.vertical, 4)
                .onChange(of: state.date) { _, _ in
                    // Close the popover as soon as a day is picked so the
                    // body / other fields behind it become interactive
                    // again (the "must fill in order" symptom).
                    showDatePopover = false
                }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return f.string(from: date)
    }

    // MARK: - Weather

    /// SF Symbol name + Chinese label. The model stores the symbol
    /// name in `state.weather` so it round-trips cleanly through the
    /// frontmatter. Custom text values that don't match any preset
    /// are stored verbatim and rendered via `Image(systemName:)`
    /// when possible (falls back to the raw text on miss).
    private struct WeatherOption: Identifiable, Hashable {
        let id: String        // SF Symbol name — used as the stored value
        let label: String     // Chinese tooltip / a11y label
    }

    private static let weatherOptions: [WeatherOption] = [
        .init(id: "sun.max.fill",            label: "晴"),
        .init(id: "cloud.sun.fill",          label: "晴间多云"),
        .init(id: "cloud.fill",              label: "多云"),
        .init(id: "cloud.drizzle.fill",      label: "小雨"),
        .init(id: "cloud.rain.fill",         label: "雨"),
        .init(id: "cloud.heavyrain.fill",    label: "大雨"),
        .init(id: "cloud.bolt.rain.fill",    label: "雷雨"),
        .init(id: "cloud.snow.fill",         label: "雪"),
        .init(id: "cloud.fog.fill",          label: "雾"),
        .init(id: "wind",                    label: "风"),
    ]

    private var weatherField: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: small label + free-form text input.
            //
            // The text field shows a *display* string: when the
            // current value matches one of our preset SF Symbols,
            // we show the human-readable Chinese label instead of
            // the raw symbol name (e.g. "雨" rather than
            // "cloud.rain.fill"). Editing the field switches the
            // value out of preset-land and into free-form text.
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("天气")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("自定义", text: weatherTextBinding)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 140)
            }
            // Icon row: one tap toggles. Tap a selected icon again
            // to clear it (same UX as the mood row).
            HStack(spacing: 4) {
                ForEach(Self.weatherOptions) { opt in
                    weatherChip(opt)
                }
                Spacer()
            }
        }
    }

    /// A two-way binding over `state.weather` that *displays* the
    /// preset's Chinese label when a preset is selected, but always
    /// writes the raw user-typed text back. This keeps the on-disk
    /// representation (the SF Symbol name, e.g. "cloud.rain.fill")
    /// while showing the user a human-readable form.
    private var weatherTextBinding: Binding<String> {
        Binding(
            get: { Self.displayLabel(for: state.weather) },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                if state.weather != trimmed {
                    state.weather = trimmed
                    state.isDirty = true
                }
            }
        )
    }

    /// If the stored value is one of our preset SF Symbol names,
    /// return the Chinese label; otherwise return the raw value
    /// (custom user text).
    private static func displayLabel(for value: String) -> String {
        if value.isEmpty { return "" }
        if let opt = weatherOptions.first(where: { $0.id == value }) {
            return opt.label
        }
        return value
    }

    private func weatherChip(_ opt: WeatherOption) -> some View {
        let isOn = state.weather == opt.id
        return Button {
            state.weather = (isOn ? "" : opt.id)
            state.isDirty = true
        } label: {
            Image(systemName: opt.id)
                .font(.callout)
                .frame(width: 30, height: 28)
                .foregroundStyle(isOn ? .white : .secondary)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? DS.Brand.amber.opacity(0.75) : Color.secondary.opacity(0.10))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isOn ? DS.Brand.amber : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(opt.label)
    }

    // MARK: - Mood

    private var moodRow: some View {
        HStack(spacing: 10) {
            Text("心情")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(1...5, id: \.self) { value in
                moodDot(value: value)
            }
            Spacer()
            aiMoodButton
        }
    }

    private func moodDot(value: Int) -> some View {
        let isOn = state.mood == value
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                state.mood = (isOn ? nil : value)
            }
        } label: {
            // Visual: 30x30 dot, kept compact so the row of 5 doesn't
            // overflow the header card on narrower windows.
            ZStack {
                Circle()
                    .fill(isOn ? moodColor(value) : Color.clear)
                    .frame(width: 30, height: 30)
                Circle()
                    .strokeBorder(moodColor(value).opacity(0.45), lineWidth: 1.5)
                    .frame(width: 30, height: 30)
                Text("\(value)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? .white : moodColor(value))
            }
            .scaleEffect(isOn ? 1.15 : 1.0)
            .shadow(color: isOn ? moodColor(value).opacity(0.55) : .clear, radius: 6, y: 2)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: isOn)
            .frame(width: 44, height: 44)        // hit area (HIG min)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(moodLabel(value))
    }

    private var aiMoodButton: some View {
        let isOn = state.mood == nil
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                state.mood = nil
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                Text("AI 决定")
                    .lineLimit(1)              // never wrap
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(isOn ? DS.Brand.amber.opacity(0.22) : Color.clear)
            }
            .overlay {
                Capsule().strokeBorder(
                    DS.Brand.amber.opacity(isOn ? 0.55 : 0.25),
                    lineWidth: 1
                )
            }
            .foregroundStyle(isOn ? DS.Brand.amber : Color.secondary)
        }
        .buttonStyle(.plain)
        .fixedSize()                          // keep natural width, don't compress
        .help("不指定心情，让 AI 根据正文推断")
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("标题")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("一句话标题（可选）", text: $state.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.medium))
        }
    }

    // MARK: - Tags

    private var tagsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("标签")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            TagsInputField(tags: $state.tags)
        }
    }

    // MARK: - Mood helpers (must match MoodBucket in Models.swift)

    private func moodColor(_ v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.55, green: 0.45, blue: 0.50)
        case 2: return Color(red: 0.72, green: 0.55, blue: 0.55)
        case 3: return Color(red: 0.85, green: 0.78, blue: 0.66)
        case 4: return Color(red: 0.91, green: 0.66, blue: 0.48)
        case 5: return DS.Brand.amber
        default: return .gray
        }
    }

    private func moodLabel(_ v: Int) -> String {
        ["", "很差", "差", "一般", "好", "很好"][v]
    }
}

// MARK: - Tags input

/// Flow-laid-out chip input. Each chip is a tag; trailing `+` adds a new one,
/// `x` on a chip removes it. Keeps the field single-line visually but
/// wraps when there's no room.
struct TagsInputField: View {
    @Binding var tags: [String]
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { idx, tag in
                chip(text: tag) { remove(at: idx) }
            }
            addField
        }
    }

    private func chip(text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text("#\(text)")
                .font(.callout)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule().fill(DS.Brand.amber.opacity(0.16))
        }
        .overlay {
            Capsule().strokeBorder(DS.Brand.amber.opacity(0.32), lineWidth: 0.5)
        }
    }

    private var addField: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("添加", text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .frame(minWidth: 50)
                .onSubmit { commit() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .strokeBorder(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 0.6, dash: [3, 2]))
        }
        .onChange(of: fieldFocused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalized = trimmed.replacingOccurrences(of: " ", with: "-")
        if !tags.contains(normalized) {
            tags.append(normalized)
        }
        draft = ""
    }

    private func remove(at idx: Int) {
        guard idx < tags.count else { return }
        tags.remove(at: idx)
    }
}
