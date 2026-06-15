import Foundation

/// "✍️ 现在写一封" — letter-writing service.
///
/// Generates the *invitation* (opening + sign-off, ~80 words) for a
/// letter based on the chosen `LetterPrompt.Scenario`. The body
/// MUST be written by the user — the LLM only sets the tone and
/// creates a soft entry-point.
///
/// Why no body from the LLM?
///   The therapeutic value of letter-writing is in the act of
///   articulating, not in reading someone else's words. Pennebaker
///   writing therapy, "unsent letter" interventions, and
///   self-compassion letter exercises all share one invariant: the
///   writer has to put their own words down. If we let the model
///   write the body, we're not healing — we're observing someone
///   else describe our feelings.
@MainActor
final class LetterService: ObservableObject {

    @Published var isLoading: Bool = false
    @Published var opening: String = ""
    @Published var error: String?

    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    /// Generate the opening for a letter. The opening is short
    /// (~80 Chinese characters), warm, and explicitly invites the
    /// user to write the rest themselves. It also produces a
    /// "sign-off" line so the user can see a complete
    /// letter-shaped frame if they want to follow it.
    func generateOpening(for scenario: LetterPrompt.Scenario) async {
        isLoading = true
        error = nil
        opening = ""
        defer { isLoading = false }

        do {
            let client = try LLMClientFactory.make(settings: settingsStore.settings)
            let system = """
                你是"拾光"app 里的"写信引导员"。你只做一件事：给用户写一封信
                的开场白和收尾，引导 ta 自己写主体。

                写作要求：
                \(scenario.systemHint)

                硬性约束：
                - 开场白 + 收尾总字数 60-100 字之间。
                - 禁止使用任何 markdown 格式（不要 #、-、*、**、[]()）。
                - 禁止使用 emoji。
                - 开头以"亲爱的"或场景的称呼起手；最后一句用很安静的语气
                  邀请对方（用户）自己继续写下去。
                - 不要给建议、不要总结、不要鸡汤。
                - 不要写"以上"、"下面"、"接下来"这种结构词。
                - 收尾留一个"—— 现在的你"或类似署名 + 一行空白。

                输出格式（必须严格遵守，不要写额外说明）：
                <开场白第一行>

                <开场白第二行（可选）>

                <一段空白>

                <署名行>
                """
            let user = "现在"
            let req = ChatRequest(
                messages: [
                    ChatMessage(role: .system, content: system),
                    ChatMessage(role: .user, content: user)
                ],
                model: settingsStore.settings.model,
                temperature: 0.85,
                maxTokens: 280
            )
            let response = try await client.chat(req)
            // Strip any leading/trailing whitespace and any
            // stray "Here's your letter:" type preamble the
            // model might add despite instructions.
            var text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Defensive: remove any markdown artefacts the model
            // might still sneak in.
            text = text
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "##", with: "")
                .replacingOccurrences(of: "—— —— ", with: "—— ")
            opening = text
        } catch {
            self.error = error.localizedDescription
            // Fall back to a templated opening so the user is
            // never blocked from writing.
            opening = fallbackOpening(for: scenario)
        }
    }

    /// Reset state when the user dismisses or switches scenarios.
    func reset() {
        opening = ""
        error = nil
    }

    private func fallbackOpening(for scenario: LetterPrompt.Scenario) -> String {
        switch scenario.id {
        case "self_3mo_ago":
            return """
            亲爱的 3 个月前的你：

            我是现在的你。我只是想告诉你，我记得你那时候在经历什么。

            你不需要现在就回信。慢慢来。

            —— 现在的你
            """
        case "self_released":
            return """
            亲爱的走出来的自己：

            我想跟你说，你做到了。不需要解释是怎么做到的——你已经做完了。

            —— 现在的你
            """
        case "self_1yr_later":
            return """
            亲爱的 1 年后的自己：

            我在 2026 年写这封信给你。你在做什么？你还好吗？

            —— 现在的你
            """
        case "person_to_forgive":
            return """
            亲爱的 ___：

            这封信你不需要看到。我只是把话写下来。

            —— 现在的你
            """
        case "self_5yr_later":
            return """
            亲爱的 5 年后的自己：

            5 年其实很短。也可以很长。你还坚持着什么吗？

            —— 现在的你
            """
        default:
            return """
            亲爱的 ___：

            我想跟你说几句话。

            —— 现在的你
            """
        }
    }
}
