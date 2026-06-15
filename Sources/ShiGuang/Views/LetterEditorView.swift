import SwiftUI

/// "✍️ 现在写一封" — letter writing sheet.
///
/// Lifecycle:
///   1. The user picks a scenario from `LetterChoiceSheet`.
///   2. `LetterEditorSheet` opens with a loading state.
///   3. `LetterService` generates the opening (~80 words) via LLM.
///   4. Once the opening is ready, the user is dropped into a
///      full `EditorView` pre-filled with the letter framing
///      (header + opening + a blank line for them to start).
///   5. Saving the editor writes the letter to today's diary file
///      via the normal `EditorView` save path.
///
/// The user can also skip the LLM and start from a blank letter
/// (the "不，AI 帮不了，我自己来" button) — in that case we open
/// `EditorView` with the empty letter framing only.
struct LetterEditorSheet: View {

    @EnvironmentObject var diaryStore: DiaryStore
    @EnvironmentObject var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let scenario: LetterPrompt.Scenario

    @StateObject private var letterService: LetterService
    @State private var phase: Phase = .loading
    @State private var errorMessage: String?

    enum Phase {
        case loading
        case ready(state: EditorState)
    }

    init(scenario: LetterPrompt.Scenario, settingsStore: SettingsStore) {
        self.scenario = scenario
        _letterService = StateObject(
            wrappedValue: LetterService(settingsStore: settingsStore)
        )
    }

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()
            switch phase {
            case .loading:
                loadingView
            case .ready(let state):
                EditorView(state: state) {
                    dismiss()
                }
                .frame(idealWidth: 820, idealHeight: 720)
            }
        }
        .task {
            // Only generate if the user has a key. If not, drop
            // straight to the editor with the framing only — they
            // can write from scratch.
            if settingsStore.settings.apiKey.isEmpty {
                phase = .ready(state: EditorState.forLetter(scenario: scenario))
                return
            }
            await letterService.generateOpening(for: scenario)
            if let err = letterService.error, !err.isEmpty {
                errorMessage = err
            }
            phase = .ready(
                state: EditorState.forLetter(
                    scenario: scenario,
                    opening: letterService.opening
                )
            )
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 18) {
            // Little ambient scene: a 3-dot pulse + the scenario
            // emoji, to give the user something to look at while
            // the LLM is generating the opening.
            Text(scenario.emoji)
                .font(.system(size: 48))
                .opacity(0.8)
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(DS.Brand.amber.opacity(0.6))
                        .frame(width: 6, height: 6)
                }
            }
            VStack(spacing: 4) {
                Text("正在写开场白…")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                Text("AI 只起头，主体由你来写。")
                    .font(.caption)
                    .foregroundStyle(DS.Brand.warmGray)
            }
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            Button {
                // Bail out of LLM, fall back to empty letter.
                phase = .ready(
                    state: EditorState.forLetter(scenario: scenario)
                )
            } label: {
                Text("不，AI 帮不了，我自己来")
                    .font(.caption)
                    .foregroundStyle(DS.Brand.warmGray)
                    .padding(.top, 12)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 560, height: 460)
    }
}
