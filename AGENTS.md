# AGENTS.md — 拾光 / AfterGlow

agent 在这个项目里工作的"项目级约定"。换到别的项目这些不一定成立；agent-level 通用技巧在 `~/.mavis/agents/mavis/memory/MEMORY.md`。

---

## 发布 / 部署

### GitHub Release 工作流（已确认 user 偏好 `allowAlways`）

- **REST API 写 GitHub 是允许的**。User 会在 message 里贴 `ghp_xxx` token 让 agent 走 `curl -H "Authorization: token ghp_xxx"`，不要为了"安全"绕到 keychain 读取（system 会再次要求授权）。
- 第一次 `curl POST` 创建 release / 上传 asset 时，bash tool 会弹 `<permission-ask>` 要求 external-write 授权。User 通常会 `allowAlways`，授权后整次 session 内的 GitHub API 写入不再问。
- **常见坑**：`git push`（HTTPS）有时会 timeout（75s+），但 `api.github.com` (HTTPS REST) 同时段正常。原因不明（可能是 git 协议握手 vs REST 不同连接复用）。**如果 push 看起来卡住，先 retry 一次；如果再卡，用 `git push &` 后台跑 + `kill -9` 兜底**。
- **先 `git ls-remote` 失败也不要立刻下结论**：可能只是当次网络抖动，再 `git push` 一次通常就过。
- 创建 release 用 `target_commitish` 时**只能传 branch 名**（如 `main`），传 commit SHA 会被 422 拒绝。

### `.dmg` 路径

- `build-app.sh` 自动打 UDZO DMG，命名 `ShiGuang-${SHORT_VERSION}.dmg`。
- **本地安装到 /Applications 的标准流程**：
  ```bash
  pkill -f ShiGuang              # 杀掉旧实例（macOS .app 二进制替换不会热生效）
  mavis-trash /Applications/ShiGuang.app
  cp -R build/ShiGuang.app /Applications/ShiGuang.app
  xattr -dr com.apple.quarantine /Applications/ShiGuang.app
  open /Applications/ShiGuang.app
  ```
- 如果 user 自己下载了 release DMG，告诉他：双击挂载 → 拖到 /Applications → 如果 Gatekeeper 弹"无法检查恶意软件"用右键打开或 `xattr`（在 README "跑起来" 段有原文）。

---

## 项目方向（product）

- **v0.2+ 核心定位**：从"日记 + AI 问答"升级到"**写作本身就是疗愈**"。
- **关键设计原则**：
  - LLM 永远不替用户写完主体（"现在写一封"的硬约束）。
  - 静态本地数据优先（今日签 0 token）vs LLM 调用（只在真正的"思考"环节）。
  - 留存机制要"gentle"——streak 跳过不扣分。
- **v0.3 候选功能**（已写进 README Roadmap）：
  - 🪞 镜像回放（echo own words, no commentary）
  - 🌧 情绪急救（mood ≤ 2 连续 3 天时温柔地展示历史）
  - 🕯 周年回响（1-year-ago today entry）
  - 📓 自我追问（LLM asks, user may answer）

---

## 代码组织（v0.2.0 之后的状态）

- **5 tabs**：写作 / 统计 / 洞察 / AI / 设置（无 TabView，永久图标 top bar）
- **品牌色**：蜜橙 `#E8A87C`（`DS.Brand.amber`），全 app 唯一 accent
- **持久化路径**：
  - `UserDefaults`: AppSettings (JSON) / `DiaryInsight.lastFolderPath` / `UpdateStore.lastAutomaticCheck` / `DailyPracticeStore.{streak,longestStreak,lastDoneDate,lastDonePromptId}`
  - `~/Library/Application Support/ShiGuang/Trash/` (回收站，软删除)
  - `~/Library/Application Support/ShiGuang/embeddings.json` (embedding 缓存 + content hash 失效)
- **LLM 默认**：MiniMax 公共 API `https://api.minimax.chat`，OpenAI Chat Completions 协议，Bearer auth，模型 `MiniMax-M2.7`（不是 Mavis 内部 `agent.minimaxi.com`）。
- **不调 LLM 的本地智能**：`NLEmbedding.wordEmbedding(for: .simplifiedChinese)` + `NLTokenizer(.word)` 做 embedding / 检索 / 关系图。
- **持久化的 frontmatter 字段**（DiaryScanner 解析）：`mood`, `mood_label`, `weather`, `tags`, `title`, `date`，其它键保留到 `extra: [String: String]`。**新增 frontmatter 字段时**优先放进 `extra` 而不是给 `Frontmatter` struct 加字段（除非真的有 UI 要读它）。

---

## changelogs/

新增 / 修改文件时，要在 `changelogs/` 下写一条 changelog（参考 git 风格）。v0.2.0 这次跳过了，应该补：

```
changelogs/2026-06-15-v0.2.0-daily-practice-and-letter.md
```

补完这条之后，下个 PR 之前的 v0.3 工作就不再依赖 git log 找信息了。
