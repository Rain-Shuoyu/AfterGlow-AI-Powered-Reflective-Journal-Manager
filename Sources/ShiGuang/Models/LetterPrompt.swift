import Foundation

/// "✍️ 现在写一封" — guided letter writing as healing practice.
///
/// The LLM only writes the *invitation* (opening + sign-off, ~80
/// words). The body must be written by the user. This is the core
/// of writing-as-therapy: articulating what you can't say aloud is
/// the work, not having a model say it for you.
struct LetterPrompt {

    /// The addressee / scenario. The user picks one before the
    /// editor opens.
    struct Scenario: Identifiable, Hashable {
        let id: String
        let emoji: String
        let displayName: String
        let tagline: String
        let example: String           // a short snippet shown on the picker card
        let recipientLabel: String   // "收信人" header in the letter
        /// System prompt hint for the LLM — frames what kind of
        /// opening the LLM should write.
        let systemHint: String
    }

    /// The five scenarios. Order is the picker order.
    static let scenarios: [Scenario] = [
        .init(
            id: "self_3mo_ago",
            emoji: "🪞",
            displayName: "3 个月前的自己",
            tagline: "焦虑 / 抑郁 / 不知道该怎么办",
            example: "那个时候你最需要听到什么？",
            recipientLabel: "亲爱的 3 个月前的你：",
            systemHint: """
                写给 3 个月前的自己。那个时候 ta 正在经历一段艰难的时间——
                焦虑、抑郁、迷茫、或者不知所措。提醒 ta 现在的自己看到
                了、记得 ta 经历了什么。不评判、不说教、不鸡汤。只是一种
                温柔的"我看见你了"。

                写法：第二人称"你"。像一封很安静的短信。
                禁止使用任何 markdown 符号（不要 # 标题、不要 - 列表、
                不要 ** 加粗）。纯段落，每段之间空一行。
                """
        ),
        .init(
            id: "self_released",
            emoji: "🕊",
            displayName: "已经释怀的某天",
            tagline: "回顾一段已经走出来的低谷",
            example: "现在回头看，那段经历给了你什么？",
            recipientLabel: "亲爱的走出来的自己：",
            systemHint: """
                写给"已经走过那段低谷的自己"。现在 ta 已经从一段
                很辛苦的日子里出来了。回看那段经历——不是感谢痛苦，
                而是说"你做到了什么"。承认自己的力量。

                写法：第二人称"你"。短句、安静的语气。
                禁止 markdown，纯段落。
                """
        ),
        .init(
            id: "self_1yr_later",
            emoji: "🌱",
            displayName: "1 年后的自己",
            tagline: "迷茫 / 想立 flag",
            example: "1 年后你想在哪？你会怎么过那一天？",
            recipientLabel: "亲爱的 1 年后的自己：",
            systemHint: """
                写给 1 年后的自己。ta 在做着什么？住在哪里？和谁
                在一起？醒来第一个动作是什么？不需要有答案，只需要
                把问题轻轻说给 ta 听。

                写法：第二人称"你"。可以是问句开始。
                禁止 markdown，纯段落。
                """
        ),
        .init(
            id: "person_to_forgive",
            emoji: "💌",
            displayName: "想原谅的人",
            tagline: "还在生气 / 内耗",
            example: "你想让他们知道你感受到了什么？",
            recipientLabel: "亲爱的 ___：",
            systemHint: """
                写给一个你想原谅的人——可能是一个具体的人、一种
                旧的关系、或者过去的自己。说出你感受到了什么，但
                不需要 ta 看到或回应。一种私下的、只给自己的释放。

                写法：第二人称"你"，或具名的"___"。不要真的写
                出对方的名字，用占位"___"代替，保护隐私。
                禁止 markdown，纯段落。
                """
        ),
        .init(
            id: "self_5yr_later",
            emoji: "🌅",
            displayName: "5 年后的自己",
            tagline: "拖延 / 不知道开始",
            example: "5 年后你理想的一天是什么样的？",
            recipientLabel: "亲爱的 5 年后的自己：",
            systemHint: """
                写给 5 年后的自己。5 年其实很短，也很长。可以问 ta：
                你做到了吗？你放弃了什么？你还坚持着什么？你在哪？
                跟谁在一起？今天的焦虑还在吗？

                写法：第二人称"你"。允许不确定、允许想象。
                禁止 markdown，纯段落。
                """
        ),
    ]

    static func scenario(id: String) -> Scenario? {
        scenarios.first { $0.id == id }
    }
}
