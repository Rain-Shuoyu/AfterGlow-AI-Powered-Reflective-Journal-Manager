import Foundation

/// "🌙 今日签" — the daily micro-practice that nudges the user into
/// a 1–2 minute self-reflection ritual on every cold start. The
/// pool is local + static (no LLM call, zero token cost). Each day
/// maps to a fixed prompt via a date-hash so the user sees the
/// same prompt all day, and it changes predictably each new day.
struct DailyPractice {

    /// A single prompt from the pool.
    struct Prompt: Identifiable, Hashable {
        let id: Int         // index in the pool — kept stable for analytics
        let category: Category
        /// The user-facing prompt, in Chinese. Single sentence, < 30 chars.
        let text: String

        enum Category: String, Hashable, CaseIterable {
            case gratitude   = "感激"
            case acknowledge = "承认"
            case dialogue    = "自我对话"
            case observe     = "观察"
            case action      = "行动"
            case question    = "问题"
            case appreciate  = "欣赏"
            case release     = "释放"
        }
    }

    /// Curated pool. Order matters only for analytics; `pick(for:)`
    /// is hash-based, not index-based. Add new prompts at the END
    /// of the array so the date-to-prompt mapping is stable across
    /// releases (don't reorder existing entries).
    static let pool: [Prompt] = [
        // ── 感激 (gratitude) ─────────────────────────────────────
        .init(id: 0,  category: .gratitude,   text: "写下 3 件今天发生的小确幸，哪怕很无聊"),
        .init(id: 1,  category: .gratitude,   text: "今天谁帮了你一个忙？哪怕对方自己都没意识到"),
        .init(id: 2,  category: .gratitude,   text: "你身体里哪个部位今天感觉舒服？"),
        // ── 承认 (acknowledge) ──────────────────────────────────
        .init(id: 3,  category: .acknowledge, text: "承认一个你今天回避的感受"),
        .init(id: 4,  category: .acknowledge, text: "你今天对自己撒了什么谎？"),
        .init(id: 5,  category: .acknowledge, text: "今天哪一刻你假装没事？"),
        // ── 自我对话 (dialogue) ─────────────────────────────────
        .init(id: 6,  category: .dialogue,    text: "用 1 句话告诉 3 个月前的自己，他现在没你想的那么糟"),
        .init(id: 7,  category: .dialogue,    text: "现在的你最想跟谁说话？写第一句"),
        .init(id: 8,  category: .dialogue,    text: "如果明天的你看到今天的记录，会说什么？"),
        // ── 观察 (observe) ──────────────────────────────────────
        .init(id: 9,  category: .observe,     text: "你今天身体哪个部位最紧绷？它在说什么？"),
        .init(id: 10, category: .observe,     text: "今天的天气和你的心情匹配吗？"),
        .init(id: 11, category: .observe,     text: "你今天笑了多少次？真的笑了几次？"),
        // ── 行动 (action) ───────────────────────────────────────
        .init(id: 12, category: .action,      text: "明天做一件 5 分钟内能完成的小事，写下来"),
        .init(id: 13, category: .action,      text: "今天能不能给别人一个具体的小帮助？"),
        .init(id: 14, category: .action,      text: "今晚睡前做一件让身体放松的事，记下是什么"),
        // ── 问题 (question) ──────────────────────────────────────
        .init(id: 15, category: .question,    text: "你现在最想被谁看见？"),
        .init(id: 16, category: .question,    text: "你最近一次说『算了』是什么时候？"),
        .init(id: 17, category: .question,    text: "你现在最害怕失去的是什么？"),
        // ── 欣赏 (appreciate) ────────────────────────────────────
        .init(id: 18, category: .appreciate,  text: "今天做的哪件事虽然没人看到，但你很为自己骄傲？"),
        .init(id: 19, category: .appreciate,  text: "你最近一次坚持完成的事是什么？"),
        .init(id: 20, category: .appreciate,  text: "你身体里哪个特质今天帮了你？"),
        // ── 释放 (release) ──────────────────────────────────────
        .init(id: 21, category: .release,     text: "写下一个你已经准备好放下的念头，一句就行"),
        .init(id: 22, category: .release,     text: "你最近在心里反复演哪段对话？让它停在这里"),
        .init(id: 23, category: .release,     text: "你今天累的不是身体，是哪里？"),
    ]

    /// Pick today's prompt. Same day → same prompt (predictable).
    /// Hash-based so it doesn't matter if the pool is reordered in a
    /// future release, *as long as we don't reorder existing
    /// entries*.
    static func pick(for date: Date = Date()) -> Prompt {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        // Encode yyyymmdd as an Int and mod-pool-size.
        let seed = (comps.year ?? 0) * 10000 + (comps.month ?? 0) * 100 + (comps.day ?? 0)
        let idx = abs(seed) % pool.count
        return pool[idx]
    }
}
