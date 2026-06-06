# 拾光 / ShiGuang · Afterglow

一个**只读**你本地 Markdown 日记的 macOS 桌面 app。零输入框 —— 选一个目录，自动出统计热力图、字数趋势、情绪分布；接 OpenAI / Anthropic 协议的大模型（默认 MiniMax），用自然语言提问日记内容。

> 拾光 —— 把过去写下的字，重新照亮一遍。

> macOS 13+ · Swift 5.9+ · 纯 SwiftUI · 单进程，无外部依赖，无网络爬虫，无第三方 SDK。

## 它能做什么

- **统计视图**
  - 52 周字数热力图（GitHub 风格）
  - 月度字数柱状图 + 平均情绪折线
  - 情绪分布直方图
  - 标签云
  - 总字数、连续天数、平均每篇字数、最近 10 篇
- **AI 助手**
  - **默认接入 MiniMax 官方公开 API**（OpenAI 协议，端点 `https://api.minimax.chat/v1/chat/completions`，模型 `MiniMax-M2.7`）
  - 同样支持 OpenAI 兼容协议（OpenAI、Azure OpenAI、vLLM、Ollama `/v1`、LocalAI…）
  - 同样支持 Anthropic Messages 协议
  - 自定义 base URL 和模型名
  - 内置日期 / 情绪 / 关键词过滤，按相关度挑出最相关的 N 篇日记再喂给模型
- **隐私**
  - 只读你的 .md 文件，从不写回
  - API Key 存 macOS Keychain，不进 UserDefaults / plist
  - 没有任何埋点或分析

## 文件结构

```
diary-insight/
├── Package.swift
├── build-app.sh                  # 打包成 .app
├── README.md
├── sample-diary/                 # 示例日记，用来跑 sanity check
│   └── 2024-06/*.md
└── Sources/DiaryInsight/
    ├── DiaryInsightApp.swift     # @main 入口 + CLI 模式
    ├── ContentView.swift         # Tab 容器
    ├── SanityCheck.swift         # 无 GUI 自检
    ├── Models/
    │   ├── Models.swift          # DiaryEntry / DiaryStats
    │   └── AppSettings.swift
    ├── Persistence/
    │   ├── DiaryStore.swift      # 扫描 + 统计的 ObservableObject
    │   └── SettingsStore.swift   # UserDefaults + Keychain
    ├── Scanner/
    │   ├── DiaryScanner.swift
    │   └── DiaryParser.swift     # YAML frontmatter + 日期/字数
    ├── Statistics/
    │   ├── StatisticsEngine.swift
    │   ├── HeatmapView.swift
    │   └── TrendChartView.swift
    ├── AI/
    │   ├── LLMClient.swift       # OpenAI + Anthropic 客户端
    │   └── DiaryIndexer.swift    # 日期/情绪/关键词过滤
    └── Views/
        ├── StatsView.swift
        ├── ChatView.swift
        └── SettingsView.swift
```

## 跑起来

### 方式 1：开发模式（最快）

```bash
cd diary-insight
swift run DiaryInsight
```

第一次会编译，~30 秒。窗口起来后：

1. 切到「**统计**」tab，点「**选择目录**」，挑你的日记目录
2. 切到「**设置**」tab —— 默认已经填好 MiniMax 官方端点 `https://api.minimax.chat` 和 `MiniMax-M2.7` 模型，**只需要填你的 API Key**（在 platform.minimaxi.com → 接口密钥 页生成）
3. 点「**测试连接**」验证
4. 切到「**AI**」tab，问问题

> 第一次安装的用户几乎不用动设置项，只填 key 就能用。想换 OpenAI / 原生 Anthropic 在下拉框里切一下，base URL 和 model 会自动换成对应默认值。

### 方式 2：打包成 .app

```bash
./build-app.sh           # release
# 或
./build-app.sh debug     # debug
```

输出在 `./build/DiaryInsight.app`，可以直接 `open` 或拖进 `/Applications`。

打包脚本做的事：
- `swift build -c <config>`
- 把 binary 拷到 `DiaryInsight.app/Contents/MacOS/`
- 生成 `Info.plist`（带最小 macOS 13、CFBundle 名、文档类型关联 Markdown）
- 生成 `PkgInfo`
- ad-hoc codesign（首次双击能过 Gatekeeper）

### 方式 3：Xocode 开发

```bash
xed Package.swift
```

Xcode 会把 SwiftPM 包当项目打开，能正常断点、Preview。

## 日记格式

文件名推荐 `YYYY-MM-DD.md`，**可选** YAML frontmatter。frontmatter 优先级 > 文件名 > 文件 mtime。

```markdown
---
date: 2024-06-05          # 留空则从文件名取
mood: 2                   # 1-5，1 最差 5 最好；用于情绪分布柱、热力图染色
mood_label: 焦虑           # 文本标签，会被映射到 1-5 桶
weather: 雨
tags: [工作, 焦虑]        # 用于标签云 + 关键词检索
title: 周二崩了             # 不写就用第一个 # 标题
---

正文从这里开始。

# 如果没 frontmatter，标题会取第一个 heading
## 副标题也 OK

代码块会被忽略，不会喂给 LLM。
```

LLM 看到的正文是 markdown 简化版（去掉标题符、链接保留文字、图片去掉 URL、引用去掉 `>`、列表去掉 marker），方便省 token。

## 检索逻辑（v1）

用户问「我六月份有哪些天心情不好？」时，indexer 做这几步：

1. **情绪词匹配**：`心情不好/难过/焦虑/开心/…` → 决定要不要过滤 mood ≤ 2 或 ≥ 4
2. **时间范围**：
   - `2024年6月` / `2024-06` / `2024/06` → 解析成具体年月
   - `June` / `Sep` → 英文月份（默认今年）
   - `上周` / `本周` / `最近` / `去年` / 裸 `2024` → 各种自然语言
3. **关键词**：分词 + 去掉停用词，对标题 / 正文 / 标签做 substring 匹配
4. **兜底**：啥都没匹配上就返回最近 30 篇

匹配到的 N 篇（默认 30，可在设置里改）拼成「【检索到的相关日记片段】」段落塞进 system prompt，再把用户原问题发出去。

**注意**：v1 没用 embedding，纯关键词 + 日期。召回不够细的话（比如「焦虑」找不到「心里发慌」），后续可以加本地 embedding 重新排序。

## 隐私 & 限制

- API Key 通过 `/usr/bin/security` 写到 macOS Keychain 的 `com.diaryinsight.apikey/default` 项
- 设置项（不含 key）写在 `~/Library/Preferences/com.apple.swift.swiftpm.pkg.DiaryInsight.plist`（或对应 bundle id）
- 网络请求只发往你在「设置」里填的 base URL，不会落到任何第三方
- 沙盒化 / 硬化版本需要单独做（codesign with Developer ID、entitlements、notarization），目前是 ad-hoc

## 已知边界

- 单日记 > 100k 字会让 `String(contentsOf:)` 慢；不是问题
- 路径里有 `〜` / `..` 的软链不会跟
- 不监听文件变化（手动点「刷新」）
- 没做单元测试，靠 `swift run DiaryInsight --sanity-check ./sample-diary` 兜底

## 升级路线

- v1.1：本地 embedding 重新排序（Ollama + bge-m3，纯本地、零成本）
- v1.2：watch 目录、文件变化自动刷新
- v1.3：导出周报 / 月报成 PDF
- v2：notarized + Mac App Store 分发

## License

MIT（随你用）。
