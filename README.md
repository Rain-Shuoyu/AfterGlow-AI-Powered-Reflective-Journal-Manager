# 拾光 · AfterGlow

> **把过去写下的字，重新照亮一遍。**
>
> 一只读你本地 Markdown 日记的 macOS 桌面 app。
> 零输入框 —— 选一个目录，统计、情绪、关系图谱自动展开；想问什么，直接问。

<p align="center">
  <img src="docs/images/hero.png" width="900" alt="拾光 hero — 拾光 / 拾光，AI 重新看见你的日记">
</p>

---

## 5 个 tab，一整天都在和过去的自己对话

| 写作 | 统计 | 洞察 | AI | 设置 |
| --- | --- | --- | --- | --- |
| Live-markdown 编辑器 | 52 周热力图 | 余弦相似度关系图 | 自由问答 | API Key / 模型 / 自定义 prompt |
| 心情 · 天气 · 标签 | 词云 / 情绪分布 | 力导向布局 | 流式结构化输出 | 检索 / 温度 / 重置 |
| 回收站（软删除 + 恢复） | 月度字数趋势 | 悬停高亮邻居 | `↩` 发送 / `⇧↩` 换行 | |

> **macOS 26+ · Apple Silicon · Swift 5.9 / 6.2 · 纯 SwiftUI · 单进程，无第三方 SDK。**

---

## ✍️ 写作

打开一篇日记就是一个**全屏编辑器**。左边是元数据（日期 / 心情 / 天气 / 标签），右边是正文。

<p align="center">
  <img src="docs/images/editor.png" width="900" alt="写作 tab — Live-markdown 编辑器，5 档心情、10 个天气预设、标签、回收站">
</p>

- **Live markdown** — `⌘B` 粗体，`⌘I` 斜体，`⌘K` 行内代码，`⌘1-6` 标题，`⌘0` 段落。Markdown 标记被渲染层藏起来，光标直接走字符之间 —— 像 Typora，但更安静。
- **5 档心情** — 自定义 30×30 dot + 44×44 命中区，按一下加 amber 发光。也可以「**AI 决定**」让模型从正文推断。
- **10 个天气预设** + 自定义文本框。选预设时文本框显示中文「雨」而不是符号 `cloud.rain.fill`，写入时还是符号（前端列表照样渲染）。
- **回收站** — `⌘⌫` 删除到 `~/Library/Application Support/ShiGuang/Trash/`，一键恢复时自动重命名去冲突。统计 / 关系图 / AI 索引**自动同步**。

---

## 📊 统计

挑一个目录，自动出 5 块内容。

<p align="center">
  <img src="docs/images/stats.png" width="900" alt="统计 tab — 52 周热力图、月度字数 + 情绪折线、情绪分布、词云">
</p>

- **52 周热力图** — GitHub 风格，琥珀色按 mtime 强度染色
- **月度字数柱 + 平均情绪折线** — 一眼看出写得多 / 心情好的月份
- **情绪分布** — 1~5 直方图
- **词云** — Wordle 风格，CJK 用 `NLTokenizer` 正确分词
- **小药丸** — 总字数、连续天数、平均每篇字数

> 全部本地计算，**零网络请求**。

---

## 🔗 洞察（关系图谱）

每篇日记 = 一个节点。**线越粗 = 越相关**。

<p align="center">
  <img src="docs/images/graph.png" width="900" alt="洞察 tab — 余弦相似度关系图，力导向布局">
</p>

- 用 Apple `NLEmbedding.wordEmbedding(.simplifiedChinese)` **本地**给每篇日记算向量
- 两两余弦相似度，**阈值 0.50** 才连线 —— 只留真有关联的
- 边宽按 `sqrt(similarity)` 拉伸，相似度越高线**明显更粗**
- **不需要 API Key** —— 纯本地，永久免费
- 悬停高亮邻居，点击节点查看完整 entry

> 缓存到 `~/Library/Application Support/ShiGuang/embeddings.json`，按内容 hash 失效 —— 100 篇日记 1 秒以内构建完成。

---

## 💬 AI 助手

问「我六月份哪些天心情不好？」「最近一个月我都关心些什么？」「我和家人之间发生过哪些冲突？」—— 模型回你一份**带标题、列表、加粗、emoji 的结构化报告**。

<p align="center">
  <img src="docs/images/chat.png" width="900" alt="AI tab — 用户问 '我六月哪些天心情不好'，AI 用结构化 Markdown 回">
</p>

- 默认接 **MiniMax 官方公开 API**（OpenAI 协议，端点 `https://api.minimax.chat/v1/chat/completions`，模型 `MiniMax-M2.7`）
- 也支持 **OpenAI / Anthropic Messages / 任何 OpenAI 兼容服务**（Azure、vLLM、Ollama…）
- **本地语义检索** —— 用上面的 `EmbeddingIndex` 算余弦相似度挑出最相关的 N 篇日记再喂给模型
- **流式输出** —— 字一个字蹦出来；结构化 Markdown 边输出边渲染
- 智能段后处理 —— 即使模型不写空行也帮你拆
- `↩` 发送，`⇧↩` 换行

---

## ⚙️ 设置

<p align="center">
  <img src="docs/images/settings.png" width="900" alt="设置 tab — LLM 提供方、API Key、检索参数、temperature、自定义系统提示词、危险操作">
</p>

切换协议下拉框，**base URL 和模型名自动换成对应默认值**。基本只需要填一个 API Key 就能用。

- **日记目录** — 选一次记住，下次启动自动恢复
- **LLM 提供方** — MiniMax / OpenAI / Anthropic，自定义 BaseURL
- **检索** — 每次送 LLM 的篇数（5–200），Temperature
- **自定义系统提示词** — 拼到默认 prompt 后面
- **危险操作** — 一键恢复所有设置

---

## 🔒 隐私

- **只读**你的 `.md` 文件，从不写回（除非你点保存）
- API Key 存**本机**，不进 plist
- 没有任何埋点 / 分析
- 网络请求**只发**到你在设置里填的 base URL

---

## 🏃 跑起来

```bash
git clone https://github.com/Rain-Shuoyu/AfterGlow-AI-Powered-Reflective-Journal-Manager
cd AfterGlow-AI-Powered-Reflective-Journal-Manager
./build-app.sh
open build/ShiGuang.app
```

第一次会编译 ~30 秒。然后：

1. 切到「**统计**」tab → 点「**选择目录**」→ 挑你的日记目录
2. 切到「**设置**」tab → 填你的 API Key（默认已经填好 MiniMax 端点）
3. 切到「**AI**」tab → 问问题
4. 切到「**洞察**」tab → 看关系图

> 想从源码开发：`xed Package.swift`，Xcode 会把 SwiftPM 当项目打开，能断点 + Preview。

---

## 📝 日记格式

文件名 `YYYY-MM-DD.md`，**可选** YAML frontmatter（推荐用）：

```markdown
---
date: 2026-06-05
mood: 2
mood_label: 焦虑
weather: cloud.rain.fill
tags: [工作, 焦虑]
title: 周二崩了
---

正文从这里开始。
```

LLM 看到的是 markdown 简化版（标题符去掉、链接保留文字、图片去掉 URL、引用去掉 `>`、列表去掉 marker），省 token。

---

## 🛠 技术栈

- Swift 5.9 / 6.2
- macOS 26+
- SwiftUI + Charts + NaturalLanguage
- SPM 构建（无 Xcode project）
- `build/ShiGuang.app` 自包含 bundle

---

## 📦 版本

[v0.1](https://github.com/Rain-Shuoyu/AfterGlow-AI-Powered-Reflective-Journal-Manager/releases/tag/v0.1) — 2026-06-08

### Roadmap

- 监听文件变化（自动刷新）
- 导出周报 / 月报成 PDF
- 多日记本（多目录切换）
- Notarized + Mac App Store 分发

---

## License

MIT。
