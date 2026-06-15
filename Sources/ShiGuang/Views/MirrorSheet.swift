import SwiftUI

/// "🪞 镜像回放" sheet — surfaces 5-7 sentences from the
/// user's past diary, picked for *diversity* (not similarity).
///
/// The sheet is deliberately quiet:
///   - No LLM commentary
///   - No emoji decoration on the sentences
///   - Generous whitespace
///   - The "🎲 换一组" button re-samples in-place
///   - "📋 复制" copies the whole reflection as a single block
struct MirrorSheet: View {

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var diaryStore: DiaryStore

    @State private var mode: MirrorSampler.Mode = .random
    @State private var reflections: [MirrorReflection] = []
    @State private var isResampling: Bool = false
    @State private var showThemePicker: Bool = false
    @State private var selectedEntry: DiaryEntry?
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if reflections.isEmpty && isResampling {
                        loadingState
                    } else if reflections.isEmpty {
                        emptyState
                    } else {
                        ForEach(reflections) { r in
                            reflectionCard(r)
                        }
                        footerActions
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 28)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 580, height: 640)
        .background {
            ZStack {
                Color(white: 0.07)
                RadialGradient(
                    colors: [DS.Brand.amber.opacity(0.06), .clear],
                    center: UnitPoint(x: 0.5, y: 0.2),
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
        .onAppear {
            resample()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("🪞")
                        .font(.system(size: 18))
                    Text("镜像")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Brand.amber.opacity(0.85))
            }
            Spacer()
            themeMenu
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
        if reflections.isEmpty { return "从你过去的日记里挑 5-7 句" }
        switch mode {
        case .random:
            return "从过去 180 天里挑了 \(reflections.count) 句"
        case .themed(let topic):
            return "关于「\(topic)」的 \(reflections.count) 句"
        }
    }

    /// Small theme-picker menu in the header. Lets the user
    /// narrow to a topic (work / relationships / self) or go
    /// back to random.
    private var themeMenu: some View {
        Menu {
            Button {
                setMode(.random)
            } label: {
                Label("随机", systemImage: "shuffle")
            }
            Divider()
            Button {
                setMode(.themed(topic: "工作"))
            } label: {
                Label("工作", systemImage: "briefcase")
            }
            Button {
                setMode(.themed(topic: "感情"))
            } label: {
                Label("感情", systemImage: "heart")
            }
            Button {
                setMode(.themed(topic: "自我"))
            } label: {
                Label("自我", systemImage: "person")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: modeIcon)
                    .font(.system(size: 11, weight: .semibold))
                Text(modeLabel)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(DS.Brand.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(DS.Brand.amber.opacity(0.15))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var modeIcon: String {
        switch mode {
        case .random: return "shuffle"
        case .themed: return "tag"
        }
    }

    private var modeLabel: String {
        switch mode {
        case .random: return "随机"
        case .themed(let t): return t
        }
    }

    private func setMode(_ m: MirrorSampler.Mode) {
        mode = m
        resample()
    }

    // MARK: - Reflection card

    private func reflectionCard(_ r: MirrorReflection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(r.text)
                .font(.system(size: 17, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(formattedDate(r.sourceDate))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Brand.warmGray)
                Spacer()
                Button {
                    if let entry = diaryStore.entries.first(where: { $0.id == r.sourceEntryId }) {
                        selectedEntry = entry
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("打开")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(DS.Brand.amber)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer actions

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button {
                copyAll()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(copied ? "已复制" : "复制整段")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(DS.Brand.warmGray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.white.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                resample()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "dice.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("换一组")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(DS.Brand.amber)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(DS.Brand.amber.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            Text("正在从你过去的日记里挑…")
                .font(.caption)
                .foregroundStyle(DS.Brand.warmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🪞")
                .font(.system(size: 36))
                .opacity(0.5)
            Text("日记还不够多")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
            Text("至少写 5 篇之后再来回看。")
                .font(.caption)
                .foregroundStyle(DS.Brand.warmGray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Helpers

    private func resample() {
        isResampling = true
        // Capture main-actor state into locals before crossing
        // the actor boundary, otherwise Swift complains about
        // `mode` and `diaryStore` being main-actor-isolated.
        let currentMode = mode
        let entries = diaryStore.entries
        Task.detached(priority: .userInitiated) {
            let sampled = MirrorSampler.sample(
                from: entries,
                mode: currentMode
            )
            await MainActor.run {
                reflections = sampled
                isResampling = false
            }
        }
    }

    private func copyAll() {
        let block = reflections
            .map { $0.text }
            .joined(separator: "\n\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(block, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }

    private func formattedDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
